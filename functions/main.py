"""Cloud Functions for Firebase (Python 3.14).

Provides geospatial nearest-neighbor queries and maintenance routines
for Radius Letters, alongside core platform tasks.
"""

import math
import json
import urllib.request
import urllib.parse
from typing import Any, Dict, List, Optional, Tuple

from firebase_functions import https_fn
from firebase_functions.options import set_global_options
from firebase_admin import initialize_app, firestore

# Keep max instances controlled to prevent unexpected compute costs
set_global_options(max_instances=10)

initialize_app()


# ---------------------------------------------------------------------------
# Pure-Python Geohash Utilities (Zero external C/binary dependencies needed)
# ---------------------------------------------------------------------------

BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
DECODE_MAP = {c: i for i, c in enumerate(BASE32)}


def encode_geohash(lat: float, lng: float, precision: int = 6) -> str:
    """Encodes (lat, lng) into a standard Base32 geohash string."""
    lat_interval = [-90.0, 90.0]
    lng_interval = [-180.0, 180.0]
    geohash: List[str] = []
    bits = [16, 8, 4, 2, 1]
    bit = 0
    ch = 0
    even = True

    while len(geohash) < precision:
        if even:
            mid = (lng_interval[0] + lng_interval[1]) / 2.0
            if lng > mid:
                ch |= bits[bit]
                lng_interval[0] = mid
            else:
                lng_interval[1] = mid
        else:
            mid = (lat_interval[0] + lat_interval[1]) / 2.0
            if lat > mid:
                ch |= bits[bit]
                lat_interval[0] = mid
            else:
                lat_interval[1] = mid
        even = not even
        if bit < 4:
            bit += 1
        else:
            geohash.append(BASE32[ch])
            bit = 0
            ch = 0
    return "".join(geohash)


def decode_geohash(geohash: str) -> Tuple[float, float, float, float]:
    """Decodes a geohash string into (lat, lng, lat_error, lng_error)."""
    lat_interval = [-90.0, 90.0]
    lng_interval = [-180.0, 180.0]
    even = True

    for c in geohash.lower():
        if c not in DECODE_MAP:
            continue
        cd = DECODE_MAP[c]
        for mask in [16, 8, 4, 2, 1]:
            if even:
                mid = (lng_interval[0] + lng_interval[1]) / 2.0
                if cd & mask:
                    lng_interval[0] = mid
                else:
                    lng_interval[1] = mid
            else:
                mid = (lat_interval[0] + lat_interval[1]) / 2.0
                if cd & mask:
                    lat_interval[0] = mid
                else:
                    lat_interval[1] = mid
            even = not even

    lat = (lat_interval[0] + lat_interval[1]) / 2.0
    lng = (lng_interval[0] + lng_interval[1]) / 2.0
    lat_err = lat_interval[1] - lat_interval[0]
    lng_err = lng_interval[1] - lng_interval[0]
    return lat, lng, lat_err, lng_err


def get_geohash_neighbors(geohash: str) -> List[str]:
    """Returns the center geohash cell plus its 8 surrounding bounding neighbors."""
    lat, lng, lat_err, lng_err = decode_geohash(geohash)
    precision = len(geohash)
    neighbors: List[str] = []

    for dlat in [-lat_err, 0.0, lat_err]:
        for dlng in [-lng_err, 0.0, lng_err]:
            n_lat = max(-90.0, min(90.0, lat + dlat))
            n_lng = lng + dlng
            if n_lng > 180.0:
                n_lng -= 360.0
            elif n_lng < -180.0:
                n_lng += 360.0
            neighbors.append(encode_geohash(n_lat, n_lng, precision))

    # Return unique cell prefixes preserving order
    return list(dict.fromkeys(neighbors))


def haversine_miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates geodesic distance in miles using the Haversine formula."""
    p = 0.017453292519943295  # math.pi / 180
    a = (
        0.5
        - math.cos((lat2 - lat1) * p) / 2.0
        + math.cos(lat1 * p)
        * math.cos(lat2 * p)
        * (1.0 - math.cos((lon2 - lon1) * p))
        / 2.0
    )
    # 12742 km * 0.621371 = Earth diameter in miles (~7917.5 mi)
    return 12742.0 * math.asin(math.sqrt(max(0.0, min(1.0, a)))) * 0.621371


def clean_location_string(raw: str) -> str:
    """Normalizes vintage state abbreviations (e.g. Wis. -> WI, Cal. -> CA)."""
    loc = raw.strip()
    replacements = [
        (r"\bWis\b\.?", "WI"),
        (r"\bIll\b\.?", "IL"),
        (r"\bMich\b\.?", "MI"),
        (r"\bMinn\b\.?", "MN"),
        (r"\bPenn\b\.?", "PA"),
        (r"\bN\.\s*D\b\.?", "ND"),
        (r"\bS\.\s*D\b\.?", "SD"),
        (r"\bCal\b\.?", "CA"),
        (r"\bCalif\b\.?", "CA"),
        (r"\bInd\b\.?", "IN"),
        (r"\bMo\b\.?", "MO"),
        (r"\bMass\b\.?", "MA"),
        (r"\bConn\b\.?", "CT"),
        (r"\bWash\b\.?", "WA"),
    ]
    import re
    for pat, rep in replacements:
        loc = re.sub(pat, rep, loc, flags=re.IGNORECASE)

    if "," in loc:
        parts = [p.strip() for p in loc.split(",")]
        if len(parts) >= 2:
            loc = f"{parts[-2]}, {parts[-1]}"
    return loc


def geocode_location_http(location_str: str) -> Optional[Dict[str, Any]]:
    """Geocodes a location string using OpenStreetMap Nominatim with clean fallback."""
    clean_loc = clean_location_string(location_str)
    if not clean_loc:
        return None

    try:
        encoded = urllib.parse.quote(clean_loc)
        url = f"https://nominatim.openstreetmap.org/search?q={encoded}&format=json&limit=1"
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "bqopd-fanzines-geocoder/1.0 (contact@bqopd.com)",
                "Accept": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode("utf-8"))
            if isinstance(data, list) and len(data) > 0:
                lat = float(data[0]["lat"])
                lng = float(data[0]["lon"])
                gh = encode_geohash(lat, lng, 6)
                return {
                    "lat": lat,
                    "lng": lng,
                    "geohash": gh,
                    "geohash_3": gh[:3],
                    "geohash_2": gh[:2],
                    "formatted": data[0].get("display_name", clean_loc),
                }
    except Exception as e:
        print(f"[geocode_location_http] Failed for '{location_str}': {e}")
    return None


# ---------------------------------------------------------------------------
# Cloud Functions Callables
# ---------------------------------------------------------------------------

@https_fn.on_call()
def query_nearest_letters(req: https_fn.CallableRequest) -> Dict[str, Any]:
    """Queries and returns the closest N historical letters to target (lat, lng).

    Expected payload:
      - lat (float): Target center latitude.
      - lng (float): Target center longitude.
      - limit (int, optional): Candidate buffer size (e.g. 20 for 4 pages, default 20, max 120).
      - max_radius_miles (float, optional): Maximum radius in miles to consider.
    """
    data = req.data or {}
    try:
        target_lat = float(data.get("lat"))
        target_lng = float(data.get("lng"))
    except (TypeError, ValueError):
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            "Valid numeric 'lat' and 'lng' parameters are required.",
        )

    limit = int(data.get("limit", 20))
    limit = max(1, min(limit, 120))  # Safeguard bounded candidate limit
    max_radius = float(data.get("max_radius_miles", 5000.0))

    db = firestore.client()
    comments_col = db.collection("artifacts").document("bqopd").collection("public").document("data").collection("comments")

    center_gh = encode_geohash(target_lat, target_lng, 6)
    seen_ids = set()
    candidate_letters: List[Dict[str, Any]] = []

    # Ring 1: Try precision 3 cells (~156km x 156km each; 3x3 grid covers ~300 mi across)
    p3_neighbors = get_geohash_neighbors(center_gh[:3])
    # Firestore 'in' query accepts up to 30 items
    p3_docs = comments_col.where(
        filter=firestore.FieldFilter("geo.geohash_3", "in", p3_neighbors)
    ).stream()

    for doc in p3_docs:
        doc_id = doc.id
        seen_ids.add(doc_id)
        doc_data = doc.to_dict() or {}
        geo = doc_data.get("geo") or {}
        l_lat = geo.get("lat")
        l_lng = geo.get("lng")
        if l_lat is not None and l_lng is not None:
            dist = haversine_miles(target_lat, target_lng, float(l_lat), float(l_lng))
            if dist <= max_radius:
                doc_data["_id"] = doc_id
                doc_data["_calculatedDistanceMiles"] = round(dist, 2)
                candidate_letters.append(doc_data)

    # Ring 2: If we don't have enough candidates, expand to precision 2 cells (~1250km)
    if len(candidate_letters) < limit:
        p2_neighbors = get_geohash_neighbors(center_gh[:2])
        p2_docs = comments_col.where(
            filter=firestore.FieldFilter("geo.geohash_2", "in", p2_neighbors)
        ).stream()

        for doc in p2_docs:
            doc_id = doc.id
            if doc_id in seen_ids:
                continue
            seen_ids.add(doc_id)
            doc_data = doc.to_dict() or {}
            geo = doc_data.get("geo") or {}
            l_lat = geo.get("lat")
            l_lng = geo.get("lng")
            if l_lat is not None and l_lng is not None:
                dist = haversine_miles(target_lat, target_lng, float(l_lat), float(l_lng))
                if dist <= max_radius:
                    doc_data["_id"] = doc_id
                    doc_data["_calculatedDistanceMiles"] = round(dist, 2)
                    candidate_letters.append(doc_data)

    # Fallback: If still under candidate limit (e.g. legacy letters not yet backfilled with geo),
    # query un-migrated letter records to ensure complete coverage.
    if len(candidate_letters) < limit:
        fallback_query = comments_col.where(
            filter=firestore.FieldFilter("sourceType", "==", "letter_column")
        ).limit(100).stream()

        for doc in fallback_query:
            doc_id = doc.id
            if doc_id in seen_ids:
                continue
            seen_ids.add(doc_id)
            doc_data = doc.to_dict() or {}
            geo = doc_data.get("geo") or {}
            l_lat = geo.get("lat")
            l_lng = geo.get("lng")

            # If document lacks geo, check if location string is available and quick-geocode
            if (l_lat is None or l_lng is None) and doc_data.get("location"):
                geocoded = geocode_location_http(str(doc_data["location"]))
                if geocoded:
                    l_lat = geocoded["lat"]
                    l_lng = geocoded["lng"]
                    # Silently patch document with newly resolved geo for future queries
                    try:
                        doc.reference.update({"geo": geocoded})
                    except Exception:
                        pass

            if l_lat is not None and l_lng is not None:
                dist = haversine_miles(target_lat, target_lng, float(l_lat), float(l_lng))
                if dist <= max_radius:
                    doc_data["_id"] = doc_id
                    doc_data["_calculatedDistanceMiles"] = round(dist, 2)
                    candidate_letters.append(doc_data)

    # Sort strictly closest-first
    candidate_letters.sort(key=lambda item: item.get("_calculatedDistanceMiles", 999999.0))

    # Slice to exact requested candidate limit
    results = candidate_letters[:limit]

    return {
        "status": "success",
        "target": {"lat": target_lat, "lng": target_lng},
        "count": len(results),
        "letters": results,
    }


@https_fn.on_call()
def fetch_static_map(req: https_fn.CallableRequest) -> Dict[str, Any]:
    """Fetches an official Google Maps Static API image server-side.

    Avoids browser CORS restrictions and prevents canvas tainting so the
    generated map image can be exported directly to Firebase Storage.
    """
    import base64

    data = req.data or {}
    markers = data.get("markers", [])
    width = int(data.get("width", 400))
    height = int(data.get("height", 640))
    scale = int(data.get("scale", 2))
    api_key = data.get("api_key") or "AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g"

    query_parts = [
        f"size={width}x{height}",
        f"scale={scale}",
        "maptype=roadmap",
        f"key={api_key}",
    ]

    # Append pins: center pin (dark red) and letter pins (Google red)
    for m in markers:
        lat = m.get("lat")
        lng = m.get("lng")
        if lat is not None and lng is not None:
            is_center = m.get("isCenter", False)
            color = "0xd32f2f" if is_center else "0xea4335"
            size = "mid" if is_center else "small"
            query_parts.append(f"markers=color:{color}%7Csize:{size}%7C{lat},{lng}")

    url = f"https://maps.googleapis.com/maps/api/staticmap?{'&'.join(query_parts)}"

    try:
        req_obj = urllib.request.Request(
            url,
            headers={
                "User-Agent": "bqopd-web/1.0",
                "Accept": "image/png,image/*",
            },
        )
        with urllib.request.urlopen(req_obj, timeout=12) as response:
            raw_bytes = response.read()
            b64_str = base64.b64encode(raw_bytes).decode("utf-8")
            return {
                "status": "success",
                "data_url": f"data:image/png;base64,{b64_str}",
            }
    except Exception as e:
        print(f"[fetch_static_map error]: {e}")
        return {
            "status": "error",
            "message": str(e),
            "fallback_url": url,
        }


@https_fn.on_call()
def backfill_letter_geocodes(req: https_fn.CallableRequest) -> Dict[str, Any]:
    """Maintenance routine: Scans existing letter comments and stamps `geo` metadata.

    Can be triggered by an administrator or curator to backfill legacy comments
    with lat, lng, and geohashes so future nearest-neighbor searches are instantaneous.
    """
    db = firestore.client()
    comments_col = db.collection("artifacts").document("bqopd").collection("public").document("data").collection("comments")

    # Fetch letters
    docs = comments_col.where(
        filter=firestore.FieldFilter("sourceType", "==", "letter_column")
    ).stream()

    updated_count = 0
    skipped_count = 0
    failed_count = 0
    cache: Dict[str, Optional[Dict[str, Any]]] = {}

    for doc in docs:
        data = doc.to_dict() or {}
        # Skip if already stamped with valid geohash
        if data.get("geo") and data["geo"].get("geohash"):
            skipped_count += 1
            continue

        raw_loc = data.get("location") or ""
        if not raw_loc.strip():
            # Check author profile if location is missing
            uid = data.get("userId")
            if uid and not str(uid).startswith("archival_"):
                try:
                    pdoc = db.collection("profiles").document(str(uid)).get()
                    if pdoc.exists:
                        pdata = pdoc.to_dict() or {}
                        raw_loc = pdata.get("location") or pdata.get("city") or ""
                        if pdata.get("state"):
                            raw_loc = f"{raw_loc}, {pdata['state']}" if raw_loc else pdata["state"]
                except Exception:
                    pass

        if not raw_loc.strip():
            skipped_count += 1
            continue

        cleaned = clean_location_string(raw_loc)
        if cleaned not in cache:
            cache[cleaned] = geocode_location_http(cleaned)

        geo_meta = cache[cleaned]
        if geo_meta:
            try:
                doc.reference.update({
                    "geo": geo_meta,
                    "location": raw_loc,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                })
                updated_count += 1
            except Exception as e:
                print(f"[backfill_letter_geocodes] Failed updating {doc.id}: {e}")
                failed_count += 1
        else:
            failed_count += 1

    return {
        "status": "complete",
        "updated": updated_count,
        "skipped": skipped_count,
        "failed": failed_count,
        "cached_locations": len(cache),
    }