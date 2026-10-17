"""Cloud Functions for Firebase (Python 3.14).

Provides server-side verified address geocoding with Firestore caching,
geospatial nearest-neighbor queries, Google Maps rasterization, baseline-grid
multi-column typography layout compilation with open-source Google Fonts
(Arimo & Anton variable fonts), font diagnostic inspection, and direct Storage
uploads for Radius Letters and Folio creation.
"""

import base64
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
import json
import math
import os
import random
import re
import string
import time
from typing import Any, Dict, List, Optional, Tuple
import urllib.parse
import urllib.request

import firebase_admin
from firebase_admin import firestore, storage
from firebase_functions import https_fn
from firebase_functions.options import set_global_options
from PIL import Image, ImageDraw, ImageFont

# Keep max instances controlled to prevent unexpected compute costs
set_global_options(max_instances=10)

# Initialize Firebase Admin SDK if not already initialized
if not firebase_admin._apps:
  firebase_admin.initialize_app()

# ---------------------------------------------------------------------------
# Layout and Baseline Grid Constants (Matching 2000x3200 Template Standard)
# ---------------------------------------------------------------------------

PAGE_WIDTH = 2000
PAGE_HEIGHT = 3200
GRID_TOP = 33
ROW_HEIGHT = 42
MAX_Y = 3120
COLUMNS_X = [33, 696, 1359]
COL_WIDTH = 608
USABLE_COL_HEIGHT = 3087

# Directory for bundled project TrueType fonts
FONTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")

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

  return list(dict.fromkeys(neighbors))

def haversine_miles(
    lat1: float, lon1: float, lat2: float, lon2: float
) -> float:
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
  for pat, rep in replacements:
    loc = re.sub(pat, rep, loc, flags=re.IGNORECASE)

  if "," in loc:
    parts = [p.strip() for p in loc.split(",")]
    if len(parts) >= 2:
      loc = f"{parts[-2]}, {parts[-1]}"
  return loc


def generate_shortcode() -> str:
  """Generates a standard Base36 7-character alphanumeric shortcode."""
  chars = string.ascii_uppercase + string.digits
  return "".join(random.choices(chars, k=7))

# ---------------------------------------------------------------------------
# Geocoding and Firestore Geo-Cache Routines
# ---------------------------------------------------------------------------

def resolve_or_cache_geocode(
    address: str, db: Optional[firestore.Client] = None
) -> Optional[Dict[str, Any]]:
  """Resolves coordinates using Firestore geocache, Google Maps API, and Nominatim fallback."""
  clean_loc = clean_location_string(address)
  if not clean_loc:
    return None

  if db is None:
    db = firestore.client()

  cache_key = re.sub(r"[^a-z0-9]+", "-", clean_loc.lower()).strip("-")
  if not cache_key:
    cache_key = "default"

  geocache_col = (
      db.collection("artifacts")
      .document("bqopd")
      .collection("public")
      .document("data")
      .collection("geocache")
  )

  # 1. Check Firestore cache first for sub-30ms returns
  try:
    cached_doc = geocache_col.document(cache_key).get()
    if cached_doc.exists:
      cached_data = cached_doc.to_dict() or {}
      if (
          cached_data.get("lat") is not None
          and cached_data.get("lng") is not None
      ):
        lat = float(cached_data["lat"])
        lng = float(cached_data["lng"])
        gh = cached_data.get("geohash") or encode_geohash(lat, lng, 6)
        return {
            "lat": lat,
            "lng": lng,
            "geohash": gh,
            "geohash_3": cached_data.get("geohash_3") or gh[:3],
            "geohash_2": cached_data.get("geohash_2") or gh[:2],
            "formatted": cached_data.get("formatted") or clean_loc,
            "city": cached_data.get("city") or "",
            "state": cached_data.get("state") or "",
            "country": cached_data.get("country") or "",
            "cached": True,
        }
  except Exception as e:
    print(
        f"[resolve_or_cache_geocode] Cache check exception for '{clean_loc}':"
        f" {e}"
    )

  resolved: Optional[Dict[str, Any]] = None
  api_key = "AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g"

  # 2. Query Google Geocoding API server-side
  try:
    encoded = urllib.parse.quote(clean_loc)
    url = (
        "https://maps.googleapis.com/maps/api/geocode/json?address="
        f"{encoded}&key={api_key}"
    )
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "bqopd-server-geocoder/1.0",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=6) as response:
      g_data = json.loads(response.read().decode("utf-8"))
      if g_data.get("status") == "OK" and g_data.get("results"):
        res0 = g_data["results"][0]
        loc = res0["geometry"]["location"]
        lat = float(loc["lat"])
        lng = float(loc["lng"])
        formatted = res0.get("formatted_address", clean_loc)

        city = ""
        state = ""
        country = ""
        for comp in res0.get("address_components", []):
          types = comp.get("types", [])
          if (
              "locality" in types
              or "sublocality" in types
              or "postal_town" in types
          ):
            if not city:
              city = comp.get("long_name") or comp.get("short_name", "")
          elif "administrative_area_level_1" in types:
            state = comp.get("short_name") or comp.get("long_name", "")
          elif "country" in types:
            country = comp.get("short_name") or comp.get("long_name", "")

        gh = encode_geohash(lat, lng, 6)
        resolved = {
            "lat": lat,
            "lng": lng,
            "geohash": gh,
            "geohash_3": gh[:3],
            "geohash_2": gh[:2],
            "formatted": formatted,
            "city": city,
            "state": state,
            "country": country,
        }
  except Exception as e:
    print(
        f"[resolve_or_cache_geocode] Google Geocoding API failed for"
        f" '{clean_loc}': {e}"
    )

  # 3. Fallback to OpenStreetMap Nominatim
  if not resolved:
    try:
      encoded = urllib.parse.quote(clean_loc)
      url = (
          "https://nominatim.openstreetmap.org/search?q="
          f"{encoded}&format=json&addressdetails=1&limit=1"
      )
      req = urllib.request.Request(
          url,
          headers={
              "User-Agent": "bqopd-fanzines-geocoder/1.0 (contact@bqopd.com)",
              "Accept": "application/json",
          },
      )
      with urllib.request.urlopen(req, timeout=6) as response:
        n_data = json.loads(response.read().decode("utf-8"))
        if isinstance(n_data, list) and len(n_data) > 0:
          lat = float(n_data[0]["lat"])
          lng = float(n_data[0]["lon"])
          gh = encode_geohash(lat, lng, 6)
          addr_details = n_data[0].get("address", {})
          city = (
              addr_details.get("city")
              or addr_details.get("town")
              or addr_details.get("village")
              or ""
          )
          state = addr_details.get("state", "")
          country = addr_details.get("country", "")
          resolved = {
              "lat": lat,
              "lng": lng,
              "geohash": gh,
              "geohash_3": gh[:3],
              "geohash_2": gh[:2],
              "formatted": n_data[0].get("display_name", clean_loc),
              "city": city,
              "state": state,
              "country": country,
          }
    except Exception as e:
      print(
          f"[resolve_or_cache_geocode] Nominatim fallback failed for"
          f" '{clean_loc}': {e}"
      )

  # 4. Save to Firestore geocache if coordinates resolved
  if resolved:
    try:
      doc_data = {
          **resolved,
          "query": address,
          "normalized": clean_loc,
          "updatedAt": firestore.SERVER_TIMESTAMP,
      }
      geocache_col.document(cache_key).set(doc_data, merge=True)
    except Exception as e:
      print(
          f"[resolve_or_cache_geocode] Failed saving cache for '{cache_key}':"
          f" {e}"
      )

    resolved["cached"] = False
    return resolved

  return None


def geocode_location_http(location_str: str) -> Optional[Dict[str, Any]]:
  """Backward-compatible helper redirecting to resolve_or_cache_geocode."""
  return resolve_or_cache_geocode(location_str)

# ---------------------------------------------------------------------------
# Server-Side Typography and Image Rasterization Engine (Pillow)
# ---------------------------------------------------------------------------

_font_cache: Dict[Tuple[str, int, bool, bool], ImageFont.ImageFont] = {}
_font_resolved_sources: Dict[Tuple[str, int, bool, bool], str] = {}


def get_font_path_candidates(
    font_family: str, bold: bool = False, italic: bool = False
) -> List[str]:
  """Generates an ordered list of candidate paths prioritizing actual bundled Google Fonts.

  Exact bundled filenames:
    - Anton-Regular.ttf
    - Arimo-VariableFont_wght.ttf
    - Arimo-Italic-VariableFont_wght.ttf
  """
  candidates: List[str] = []
  f_lower = font_family.lower()

  # 1. Bundled project fonts folder (functions/fonts/)
  if "anton" in f_lower:
    candidates.extend([
        os.path.join(FONTS_DIR, "Anton-Regular.ttf"),
        os.path.join(FONTS_DIR, "anton.ttf"),
        os.path.join(FONTS_DIR, "Anton.ttf"),
    ])
  elif italic:
    candidates.extend([
        os.path.join(FONTS_DIR, "Arimo-Italic-VariableFont_wght.ttf"),
        os.path.join(FONTS_DIR, "Arimo-VariableFont_wght.ttf"),
        os.path.join(FONTS_DIR, "Arimo-Regular.ttf"),
        os.path.join(FONTS_DIR, "LiberationSans-Italic.ttf"),
        os.path.join(FONTS_DIR, "DejaVuSans-Oblique.ttf"),
    ])
  else:
    candidates.extend([
        os.path.join(FONTS_DIR, "Arimo-VariableFont_wght.ttf"),
        os.path.join(FONTS_DIR, "Arimo-Regular.ttf"),
        os.path.join(FONTS_DIR, "Arimo-Bold.ttf"),
        os.path.join(FONTS_DIR, "arimobd.ttf"),
        os.path.join(FONTS_DIR, "LiberationSans-Regular.ttf"),
        os.path.join(FONTS_DIR, "DejaVuSans.ttf"),
    ])

  # 2. Linux / Debian Container System Fonts (Fallback)
  if "anton" in f_lower:
    candidates.extend([
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ])
  elif bold:
    candidates.extend([
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    ])
  else:
    candidates.extend([
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    ])

  return candidates

def get_font(
    font_family: str, size: int, bold: bool = False, italic: bool = False
) -> ImageFont.ImageFont:
  """Loads a TTF font matching browser rendering, configuring variable font weight axes."""
  cache_key = (font_family.lower(), size, bold, italic)
  if cache_key in _font_cache:
    return _font_cache[cache_key]

  candidates = get_font_path_candidates(font_family, bold=bold, italic=italic)
  font_obj: Optional[ImageFont.ImageFont] = None
  resolved_path: str = "fallback_default"

  for path in candidates:
    if os.path.exists(path):
      try:
        font_obj = ImageFont.truetype(path, size=size)
        if "variablefont" in path.lower():
          target_weight = 700 if bold else 400
          try:
            if hasattr(font_obj, "set_variation_by_axes"):
              font_obj.set_variation_by_axes([target_weight])
            elif hasattr(font_obj, "set_variation_by_name"):
              font_obj.set_variation_by_name("Bold" if bold else "Regular")
          except Exception:
            pass
        resolved_path = path
        break
      except Exception:
        continue

  if font_obj is None:
    try:
      font_obj = ImageFont.truetype("DejaVuSans.ttf", size=size)
      resolved_path = "system_dejavu_name"
    except Exception:
      font_obj = ImageFont.load_default()
      resolved_path = "pillow_internal_default"

  _font_cache[cache_key] = font_obj
  _font_resolved_sources[cache_key] = resolved_path
  return font_obj


def measure_text_width(text: str, font: ImageFont.ImageFont) -> float:
  """Calculates horizontal pixel width of a string with sub-pixel accuracy."""
  if not text:
    return 0.0
  try:
    bbox = font.getbbox(text)
    return float(bbox[2] - bbox[0])
  except Exception:
    return float(len(text) * 16)


def wrap_text_words(
    text_to_wrap: str, font: ImageFont.ImageFont, max_width: float
) -> List[str]:
  """Wraps text into lines that do not exceed max_width."""
  words = text_to_wrap.split(" ")
  lines: List[str] = []
  current_line = ""

  for word in words:
    test_line = f"{current_line} {word}" if current_line else word
    if measure_text_width(test_line, font) > max_width:
      if current_line:
        lines.append(current_line)
      current_line = word
    else:
      current_line = test_line

  if current_line:
    lines.append(current_line)
  return lines


def snap_to_grid(y: float) -> float:
  """Snaps a vertical coordinate to the nearest baseline grid row."""
  if y <= GRID_TOP:
    return float(GRID_TOP)
  rows = math.ceil((y - GRID_TOP) / float(ROW_HEIGHT))
  return float(GRID_TOP + (rows * ROW_HEIGHT))

def init_page_canvas() -> Tuple[Image.Image, ImageDraw.ImageDraw]:
  """Initializes a blank 2000x3200 page canvas with outer border and column dividers."""
  canvas = Image.new("RGB", (PAGE_WIDTH, PAGE_HEIGHT), color=(255, 255, 255))
  ctx = ImageDraw.Draw(canvas)

  # Outer border (11px stroke width)
  ctx.rectangle(
      [5, 5, PAGE_WIDTH - 6, PAGE_HEIGHT - 6], outline=(0, 0, 0), width=11
  )

  # Two column divider lines at x=663 and x=1326
  ctx.rectangle([663, 99, 663 + 11, 3101], fill=(0, 0, 0))
  ctx.rectangle([1326, 99, 1326 + 11, 3101], fill=(0, 0, 0))

  return canvas, ctx


def download_remote_image(url: str, timeout: int = 6) -> Optional[Image.Image]:
  """Downloads and decodes an image URL into a Pillow Image."""
  if not url or not url.strip().startswith("http"):
    return None
  try:
    req = urllib.request.Request(
        url.strip(),
        headers={"User-Agent": "bqopd-server-publisher/1.0"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
      data = resp.read()
      img = Image.open(BytesIO(data))
      if img.mode in ("RGBA", "P"):
        img = img.convert("RGB")
      return img
  except Exception as e:
    print(f"[download_remote_image] Could not fetch '{url}': {e}")
    return None

def upload_three_webp_scales(
    canvas: Image.Image,
    bucket: Any,
    storage_prefix: str,
    token: str,
) -> Tuple[str, str, str]:
  """Compresses canvas into original (2000x3200), list (800x1280), and grid (450x720) WebPs.

  Uploads all three directly to Cloud Storage with metadata and returns public URLs.
  Redundant blob.patch() calls are eliminated to maximize throughput.
  """
  # 1. Original (2000x3200)
  orig_io = BytesIO()
  canvas.save(orig_io, format="WEBP", quality=90)
  orig_bytes = orig_io.getvalue()

  # 2. List (800x1280)
  list_img = canvas.resize((800, 1280), Image.Resampling.LANCZOS)
  list_io = BytesIO()
  list_img.save(list_io, format="WEBP", quality=80)
  list_bytes = list_io.getvalue()

  # 3. Grid (450x720)
  grid_img = canvas.resize((450, 720), Image.Resampling.LANCZOS)
  grid_io = BytesIO()
  grid_img.save(grid_io, format="WEBP", quality=80)
  grid_bytes = grid_io.getvalue()

  def _upload(filename: str, raw_bytes: bytes) -> str:
    full_path = f"{storage_prefix}/{filename}"
    blob = bucket.blob(full_path)
    blob.metadata = {"firebaseStorageDownloadTokens": token}
    blob.upload_from_string(raw_bytes, content_type="image/webp")
    encoded = urllib.parse.quote(full_path, safe="")
    cb = int(time.time() * 1000)
    return (
        f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{encoded}?alt=media&token={token}&cb={cb}"
    )

  orig_url = _upload("original.webp", orig_bytes)
  list_url = _upload("list.webp", list_bytes)
  grid_url = _upload("grid.webp", grid_bytes)
  return orig_url, list_url, grid_url

def parse_markdown_to_blocks(raw_text: str) -> List[Dict[str, Any]]:
  """Parses markdown into typed blocks for the 3-column publisher layout engine."""
  blocks: List[Dict[str, Any]] = []
  current_paragraph = ""

  def commit_paragraph():
    nonlocal current_paragraph
    p_text = current_paragraph.strip()
    if not p_text:
      return

    image_regex = r"^\{\{IMAGE(?::\s*(.*?))?\}\}$"
    template_regex = r"^\{\{TEMPLATE_(\d+):\s*([^|]+)\s*\|\s*(.*?)\}\}$"
    col_break_regex = r"^(?:\{\{|\[\[)COLUMN_BREAK(?:\}\}|\]\])$"

    m_img = re.match(image_regex, p_text, flags=re.IGNORECASE)
    m_tmpl = re.match(template_regex, p_text, flags=re.IGNORECASE)
    m_cb = re.match(col_break_regex, p_text, flags=re.IGNORECASE)

    if m_img:
      blocks.append({
          "type": "image",
          "url": m_img.group(1).strip() if m_img.group(1) else "",
      })
    elif m_tmpl:
      t_num = int(m_tmpl.group(1))
      t_url = m_tmpl.group(2).strip()
      rest = m_tmpl.group(3).strip()
      target_row = None
      caption_text = rest
      row_match = re.match(
          r"^row=(\d+)\s*\|\s*(.*)$", rest, flags=re.IGNORECASE
      )
      if row_match:
        target_row = int(row_match.group(1))
        caption_text = row_match.group(2).strip()

      blocks.append({"type": "column_break"})
      blocks.append({
          "type": "template_block",
          "templateNum": t_num,
          "url": t_url,
          "content": caption_text,
          "targetRow": target_row,
      })
      blocks.append({"type": "column_break"})
    elif m_cb or p_text.lower() in ("column-break", "column_break"):
      blocks.append({"type": "column_break"})
    elif p_text.startswith("### "):
      blocks.append(
          {"type": "h3", "content": p_text[4:].strip(), "raw": p_text}
      )
    elif p_text.startswith("## "):
      blocks.append(
          {"type": "h2", "content": p_text[3:].strip(), "raw": p_text}
      )
    elif p_text.startswith("# "):
      blocks.append(
          {"type": "h1", "content": p_text[2:].strip(), "raw": p_text}
      )
    elif p_text.startswith("* ") or p_text.startswith("- "):
      blocks.append(
          {"type": "bullet", "content": p_text[2:].strip(), "raw": p_text}
      )
    else:
      blocks.append({"type": "text", "content": p_text, "raw": p_text})

    current_paragraph = ""

  lines = raw_text.split("\n")
  for line in lines:
    clean_line = line.strip()
    if clean_line == "":
      commit_paragraph()
    elif (
        clean_line.startswith("# ")
        or clean_line.startswith("## ")
        or clean_line.startswith("### ")
        or clean_line.startswith("* ")
        or clean_line.startswith("- ")
        or clean_line.startswith("{{")
        or clean_line.startswith("[[")
    ):
      commit_paragraph()
      current_paragraph = clean_line
      commit_paragraph()
    else:
      if current_paragraph:
        current_paragraph += " " + clean_line
      else:
        current_paragraph = clean_line

  commit_paragraph()
  return blocks

def render_publisher_pages_internal(
    raw_text: str,
) -> List[Tuple[Image.Image, str]]:
  """Lays out and rasterizes markdown text across 2000x3200 3-column canvases in Pillow with Anton & Arimo."""
  pages_results: List[Tuple[Image.Image, str]] = []
  blocks = parse_markdown_to_blocks(raw_text)

  active_canvas, ctx = init_page_canvas()
  col_index = 0
  current_y = float(GRID_TOP)
  current_page_text_parts: List[str] = []

  def finalize_current_page():
    nonlocal active_canvas, ctx, col_index, current_y, current_page_text_parts
    page_text = "\n\n".join(current_page_text_parts).strip()
    pages_results.append((active_canvas, page_text))
    active_canvas, ctx = init_page_canvas()
    col_index = 0
    current_y = float(GRID_TOP)
    current_page_text_parts = []

  def advance_to_next_column():
    nonlocal col_index, current_y
    col_index += 1
    current_y = float(GRID_TOP)
    if col_index >= 3:
      finalize_current_page()

  for block in blocks:
    b_type = block.get("type")

    if b_type == "column_break":
      if current_y > GRID_TOP:
        advance_to_next_column()
      continue

    if b_type == "image":
      target_url = block.get("url", "")
      img_obj = download_remote_image(target_url) if target_url else None
      draw_height = 400
      if img_obj and img_obj.width > 0 and img_obj.height > 0:
        draw_height = int(COL_WIDTH * (img_obj.height / float(img_obj.width)))

      min_margin_bottom = 14
      rows_needed = math.ceil(
          (draw_height + min_margin_bottom) / float(ROW_HEIGHT)
      )
      total_image_block_height = int(rows_needed * ROW_HEIGHT)

      if current_y + total_image_block_height > MAX_Y:
        advance_to_next_column()

      x = COLUMNS_X[col_index]
      y = int(current_y)

      if img_obj:
        resized_img = img_obj.resize(
            (COL_WIDTH, draw_height), Image.Resampling.LANCZOS
        )
        active_canvas.paste(resized_img, (x, y))
      else:
        ctx.rectangle(
            [x, y, x + COL_WIDTH, y + draw_height],
            fill=(243, 244, 246),
            outline=(209, 213, 219),
            width=2,
        )
        ctx.line(
            [x + 10, y + 10, x + COL_WIDTH - 10, y + draw_height - 10],
            fill=(209, 213, 219),
            width=2,
        )
        ctx.line(
            [x + COL_WIDTH - 10, y + 10, x + 10, y + draw_height - 10],
            fill=(209, 213, 219),
            width=2,
        )

      current_y += float(total_image_block_height)
      current_page_text_parts.append(f"{{{{IMAGE: {target_url}}}}}")

    elif b_type == "template_block" and block.get("templateNum") == 1:
      target_url = block.get("url", "")
      caption = block.get("content", "")
      target_row = block.get("targetRow")

      img_obj = download_remote_image(target_url) if target_url else None
      img_height = 400
      if img_obj and img_obj.width > 0 and img_obj.height > 0:
        img_height = int(COL_WIDTH * (img_obj.height / float(img_obj.width)))

      font_caption = get_font("Arimo", 24, bold=False)
      lines_to_draw = wrap_text_words(caption, font_caption, COL_WIDTH)
      text_leading_step = 24.0 * 1.4
      total_text_height = len(lines_to_draw) * text_leading_step + 12.0

      x = COLUMNS_X[col_index]

      if target_row is not None:
        target_y_bottom = GRID_TOP + target_row * ROW_HEIGHT
        target_y_top = target_y_bottom - img_height
        if (
            current_y > target_y_top
            or target_y_bottom + total_text_height > MAX_Y
        ):
          advance_to_next_column()
          x = COLUMNS_X[col_index]
          target_y_bottom = GRID_TOP + target_row * ROW_HEIGHT
          target_y_top = target_y_bottom - img_height

        if img_obj:
          resized = img_obj.resize(
              (COL_WIDTH, img_height), Image.Resampling.LANCZOS
          )
          active_canvas.paste(resized, (x, int(target_y_top)))
        else:
          ctx.rectangle(
              [
                  x,
                  int(target_y_top),
                  x + COL_WIDTH,
                  int(target_y_top + img_height),
              ],
              fill=(243, 244, 246),
          )

        caption_y = target_y_top + img_height + 16.0
        for line in lines_to_draw:
          ctx.text((x, caption_y), line, font=font_caption, fill=(26, 26, 26))
          caption_y += text_leading_step
        current_y = snap_to_grid(caption_y + 14.0)
      else:
        composite_height = img_height + total_text_height + 20.0
        rows_needed = math.ceil((composite_height + 14.0) / float(ROW_HEIGHT))
        total_block_height = rows_needed * ROW_HEIGHT

        if current_y + total_block_height > MAX_Y:
          advance_to_next_column()
          x = COLUMNS_X[col_index]

        if img_obj:
          resized = img_obj.resize(
              (COL_WIDTH, img_height), Image.Resampling.LANCZOS
          )
          active_canvas.paste(resized, (x, int(current_y)))
        else:
          ctx.rectangle(
              [x, int(current_y), x + COL_WIDTH, int(current_y + img_height)],
              fill=(243, 244, 246),
          )

        caption_y = current_y + img_height + 16.0
        for line in lines_to_draw:
          ctx.text((x, caption_y), line, font=font_caption, fill=(26, 26, 26))
          caption_y += text_leading_step
        current_y += float(total_block_height)

      current_page_text_parts.append(
          f"{{{{TEMPLATE_1: {target_url} | {caption}}}}}"
      )

    else:
      font_size = 28
      font_family = "Arimo"
      is_bold = False
      step = float(ROW_HEIGHT)

      if b_type == "h1":
        font_size = 42
        font_family = "Anton"
        is_bold = False
        step = 56.0
      elif b_type == "h2":
        font_size = 36
        font_family = "Anton"
        is_bold = False
        step = 48.0
      elif b_type == "h3":
        font_size = 28
        font_family = "Anton"
        is_bold = False
        step = float(ROW_HEIGHT)
      else:
        font_size = 28
        font_family = "Arimo"
        is_bold = False
        step = float(ROW_HEIGHT)

      font = get_font(font_family, font_size, bold=is_bold)
      content_str = block.get("content", "")
      is_bullet = b_type == "bullet"
      text_to_wrap = f"    {content_str}" if is_bullet else content_str

      lines_to_draw = wrap_text_words(text_to_wrap, font, COL_WIDTH)
      current_paragraph_lines: List[str] = []

      for i, line in enumerate(lines_to_draw):
        if current_y + font_size > MAX_Y:
          if current_paragraph_lines:
            current_page_text_parts.append(" ".join(current_paragraph_lines))
            current_paragraph_lines = []
          advance_to_next_column()

        x = COLUMNS_X[col_index]
        is_last_line = i == len(lines_to_draw) - 1

        if not is_last_line and b_type == "text" and len(lines_to_draw) > 1:
          words = line.split(" ")
          if len(words) > 1:
            words_w = sum(measure_text_width(w, font) for w in words)
            spacing = (COL_WIDTH - words_w) / float(len(words) - 1)
            curr_x = float(x)
            for w in words:
              ctx.text((curr_x, current_y), w, font=font, fill=(26, 26, 26))
              curr_x += measure_text_width(w, font) + spacing
          else:
            ctx.text((x, current_y), line, font=font, fill=(26, 26, 26))
        else:
          ctx.text((x, current_y), line, font=font, fill=(26, 26, 26))

        current_y += step
        current_paragraph_lines.append(line)

      current_y = snap_to_grid(current_y + 14.0)

      if current_paragraph_lines:
        if b_type == "h1":
          current_page_text_parts.append(
              "# " + " ".join(current_paragraph_lines)
          )
        elif b_type == "h2":
          current_page_text_parts.append(
              "## " + " ".join(current_paragraph_lines)
          )
        elif b_type == "h3":
          current_page_text_parts.append(
              "### " + " ".join(current_paragraph_lines)
          )
        elif b_type == "bullet":
          current_page_text_parts.append(
              "* " + " ".join(current_paragraph_lines)
          )
        else:
          current_page_text_parts.append(" ".join(current_paragraph_lines))

  if current_y > GRID_TOP or col_index > 0:
    finalize_current_page()

  return pages_results

# ---------------------------------------------------------------------------
# Cloud Functions Callables: Diagnostics, Geocoding, Search, and Map Cover
# ---------------------------------------------------------------------------

@https_fn.on_call()
def check_server_fonts(req: https_fn.CallableRequest) -> Dict[str, Any]:
  """Diagnostic callable to inspect font availability and test-render on server."""
  fonts_dir_exists = os.path.exists(FONTS_DIR)
  bundled_files = os.listdir(FONTS_DIR) if fonts_dir_exists else []

  system_paths = [
      "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
      "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
  ]
  system_found = [p for p in system_paths if os.path.exists(p)]

  tests = {}
  for family, sz, bold, name in [
      ("Anton", 42, False, "Anton_42"),
      ("Arimo", 36, True, "Arimo_Bold_36"),
      ("Arimo", 28, False, "Arimo_28"),
  ]:
    f_obj = get_font(family, sz, bold=bold)
    source = _font_resolved_sources.get(
        (family.lower(), sz, bold, False), "unknown"
    )
    width = measure_text_width("THE FANTASY FAN 1934", f_obj)
    tests[name] = {
        "source": source,
        "is_bundled": source.startswith(FONTS_DIR),
        "width_sample": width,
        "is_default_fallback": source == "pillow_internal_default",
    }

  return {
      "status": "success",
      "fonts_dir": FONTS_DIR,
      "fonts_dir_exists": fonts_dir_exists,
      "bundled_fonts_found": bundled_files,
      "system_fonts_found": system_found,
      "test_render": tests,
  }

@https_fn.on_call()
def geocode_address(req: https_fn.CallableRequest) -> Dict[str, Any]:
  """Server-side verified address geocoding with Firestore caching."""
  data = req.data or {}
  raw_address = data.get("address", "")
  if not isinstance(raw_address, str) or not raw_address.strip():
    raise https_fn.HttpsError(
        https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
        "An 'address' string parameter is required.",
    )

  res = resolve_or_cache_geocode(raw_address.strip())
  if res:
    return {
        "status": "success",
        **res,
    }

  return {
      "status": "error",
      "message": (
          f"Could not resolve geographic coordinates for '{raw_address}'."
      ),
  }


@https_fn.on_call()
def query_nearest_letters(req: https_fn.CallableRequest) -> Dict[str, Any]:
  """Queries and returns the closest N historical letters to target (lat, lng)."""
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
  limit = max(1, min(limit, 160))
  max_radius = float(data.get("max_radius_miles", 5000.0))

  db = firestore.client()
  comments_col = (
      db.collection("artifacts")
      .document("bqopd")
      .collection("public")
      .document("data")
      .collection("comments")
  )

  center_gh = encode_geohash(target_lat, target_lng, 6)
  seen_ids = set()
  candidate_letters: List[Dict[str, Any]] = []

  # Ring 1: Precision 3 cells (~156km x 156km each; 3x3 grid covers ~300 mi across)
  p3_neighbors = get_geohash_neighbors(center_gh[:3])
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

  # Ring 2: Precision 2 cells (~1250km)
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
        dist = haversine_miles(
            target_lat, target_lng, float(l_lat), float(l_lng)
        )
        if dist <= max_radius:
          doc_data["_id"] = doc_id
          doc_data["_calculatedDistanceMiles"] = round(dist, 2)
          candidate_letters.append(doc_data)

  # Fallback: Query un-migrated letter records with cached resolver
  if len(candidate_letters) < limit:
    fallback_query = (
        comments_col.where(
            filter=firestore.FieldFilter("sourceType", "==", "letter_column")
        )
        .limit(100)
        .stream()
    )

    for doc in fallback_query:
      doc_id = doc.id
      if doc_id in seen_ids:
        continue
      seen_ids.add(doc_id)
      doc_data = doc.to_dict() or {}
      geo = doc_data.get("geo") or {}
      l_lat = geo.get("lat")
      l_lng = geo.get("lng")

      if (l_lat is None or l_lng is None) and doc_data.get("location"):
        geocoded = resolve_or_cache_geocode(str(doc_data["location"]), db=db)
        if geocoded:
          l_lat = geocoded["lat"]
          l_lng = geocoded["lng"]
          try:
            doc.reference.update({"geo": geocoded})
          except Exception:
            pass

      if l_lat is not None and l_lng is not None:
        dist = haversine_miles(
            target_lat, target_lng, float(l_lat), float(l_lng)
        )
        if dist <= max_radius:
          doc_data["_id"] = doc_id
          doc_data["_calculatedDistanceMiles"] = round(dist, 2)
          candidate_letters.append(doc_data)

  candidate_letters.sort(
      key=lambda item: item.get("_calculatedDistanceMiles", 999999.0)
  )
  results = candidate_letters[:limit]

  return {
      "status": "success",
      "target": {"lat": target_lat, "lng": target_lng},
      "count": len(results),
      "letters": results,
  }

@https_fn.on_call()
def fetch_static_map(req: https_fn.CallableRequest) -> Dict[str, Any]:
  """Fetches an official Google Maps Static API image server-side."""
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
  """Maintenance routine: Scans existing letter comments and stamps `geo` metadata."""
  db = firestore.client()
  comments_col = (
      db.collection("artifacts")
      .document("bqopd")
      .collection("public")
      .document("data")
      .collection("comments")
  )

  docs = comments_col.where(
      filter=firestore.FieldFilter("sourceType", "==", "letter_column")
  ).stream()

  updated_count = 0
  skipped_count = 0
  failed_count = 0
  cache: Dict[str, Optional[Dict[str, Any]]] = {}

  for doc in docs:
    data = doc.to_dict() or {}
    if data.get("geo") and data["geo"].get("geohash"):
      skipped_count += 1
      continue

    raw_loc = data.get("location") or ""
    if not raw_loc.strip():
      uid = data.get("userId")
      if uid and not str(uid).startswith("archival_"):
        try:
          pdoc = db.collection("profiles").document(str(uid)).get()
          if pdoc.exists:
            pdata = pdoc.to_dict() or {}
            raw_loc = pdata.get("location") or pdata.get("city") or ""
            if pdata.get("state"):
              raw_loc = (
                  f"{raw_loc}, {pdata['state']}" if raw_loc else pdata["state"]
              )
        except Exception:
          pass

    if not raw_loc.strip():
      skipped_count += 1
      continue

    cleaned = clean_location_string(raw_loc)
    if cleaned not in cache:
      cache[cleaned] = resolve_or_cache_geocode(cleaned, db=db)

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

# ---------------------------------------------------------------------------
# Cloud Functions Callables: Heavy Server-Side Layout & WebP Compilation
# ---------------------------------------------------------------------------

@https_fn.on_call(memory=2048, timeout_sec=300, cpu=2)
def compile_publisher_folio(req: https_fn.CallableRequest) -> Dict[str, Any]:
  """Compiles multi-page continuous markdown text into 2000x3200 publisher pages.

  Renders layouts on a 42px baseline grid in Pillow with Anton & Arimo variable fonts,
  generates 3-size WebP binaries (original, list, grid) with multithreaded uploads,
  streams them to Cloud Storage with 2 vCPUs and 2048MB RAM, and registers the Firestore documents.
  """
  data = req.data or {}
  fanzine_id = data.get("fanzineId")
  full_text = data.get("fullText", "")
  owner_user_id = data.get("ownerUserId") or (
      req.auth.uid if req.auth else "system_web"
  )
  template_id = data.get("templateId", "basic_text")
  start_page_number = int(data.get("startPageNumber", 1))

  if not fanzine_id or not full_text.strip():
    raise https_fn.HttpsError(
        https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
        "Both 'fanzineId' and non-empty 'fullText' parameters are required.",
    )

  db = firestore.client()
  bucket = storage.bucket()

  pages_and_text = render_publisher_pages_internal(full_text)
  if not pages_and_text:
    return {"status": "success", "count": 0, "pages": []}

  now_ms = int(time.time() * 1000)

  def _process_and_upload_page(
      task: Tuple[int, Image.Image, str],
  ) -> Tuple[int, Dict[str, Any]]:
    i, canvas, page_text = task
    page_num = start_page_number + i
    page_image_id = f"folio_text_page_{now_ms}_{page_num}"
    page_id = f"page_{now_ms}_{page_num}"
    short_code = generate_shortcode()
    storage_prefix = (
        f"uploads/{owner_user_id}/folio_assets/{fanzine_id}/{page_image_id}"
    )

    orig_url, list_url, grid_url = upload_three_webp_scales(
        canvas=canvas,
        bucket=bucket,
        storage_prefix=storage_prefix,
        token=page_image_id,
    )

    image_metadata = {
        "uid": owner_user_id,
        "uploaderId": owner_user_id,
        "type": "template",
        "templateId": template_id,
        "text": page_text,
        "text_corrected": page_text,
        "text_linked": page_text,
        "title": f"Letters Page {page_num}",
        "isGenerated": True,
        "width": PAGE_WIDTH,
        "height": PAGE_HEIGHT,
        "aspectRatio": 0.625,
        "is5x8": True,
        "shortCode": short_code,
        "folioContext": fanzine_id,
        "usedInFanzines": [fanzine_id],
        "fileUrl": orig_url,
        "listUrl": list_url,
        "gridUrl": grid_url,
        "timestamp": firestore.SERVER_TIMESTAMP,
    }
    db.collection("images").document(page_image_id).set(
        image_metadata, merge=True
    )

    return i, {
        "id": page_id,
        "pageNumber": page_num,
        "imageId": page_image_id,
        "imageUrl": orig_url,
        "gridUrl": grid_url,
        "listUrl": list_url,
        "status": "ready",
        "templateId": template_id,
        "width": PAGE_WIDTH,
        "height": PAGE_HEIGHT,
        "is5x8": True,
    }

  tasks = [
      (i, canvas, page_text)
      for i, (canvas, page_text) in enumerate(pages_and_text)
  ]
  worker_count = min(8, len(tasks)) if tasks else 1

  with ThreadPoolExecutor(max_workers=worker_count) as executor:
    results = list(executor.map(_process_and_upload_page, tasks))

  results.sort(key=lambda r: r[0])
  output_pages = [page_dict for _, page_dict in results]

  return {
      "status": "success",
      "fanzineId": fanzine_id,
      "count": len(output_pages),
      "pages": output_pages,
  }

@https_fn.on_call(memory=512, timeout_sec=120)
def compile_publisher_page(req: https_fn.CallableRequest) -> Dict[str, Any]:
  """Re-compiles a single 2000x3200 page from markdown and uploads WebP scales.

  Used by the text and publisher editors when updating individual pages.
  """
  data = req.data or {}
  fanzine_id = data.get("fanzineId")
  image_id = data.get("imageId")
  text = data.get("text", "")
  owner_user_id = data.get("ownerUserId") or (
      req.auth.uid if req.auth else "system_web"
  )
  template_id = data.get("templateId", "basic_text")

  if not fanzine_id or not image_id or not text.strip():
    raise https_fn.HttpsError(
        https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
        "'fanzineId', 'imageId', and 'text' parameters are required.",
    )

  db = firestore.client()
  bucket = storage.bucket()

  pages = render_publisher_pages_internal(text)
  canvas = pages[0][0] if pages else init_page_canvas()[0]
  storage_prefix = f"uploads/{owner_user_id}/folio_assets/{fanzine_id}/{image_id}"

  orig_url, list_url, grid_url = upload_three_webp_scales(
      canvas=canvas,
      bucket=bucket,
      storage_prefix=storage_prefix,
      token=image_id,
  )

  db.collection("images").document(image_id).set(
      {
          "fileUrl": orig_url,
          "listUrl": list_url,
          "gridUrl": grid_url,
          "status": "ready",
          "updatedAt": firestore.SERVER_TIMESTAMP,
      },
      merge=True,
  )

  return {
      "status": "success",
      "fileUrl": orig_url,
      "listUrl": list_url,
      "gridUrl": grid_url,
  }

@https_fn.on_call(memory=512, timeout_sec=120)
def compile_map_cover(req: https_fn.CallableRequest) -> Dict[str, Any]:
  """Generates an illustrated 2000x3200 Google Maps cover page with radial markers.

  Uploads 3 WebP sizes directly to Cloud Storage and registers the image record.
  """
  data = req.data or {}
  fanzine_id = data.get("fanzineId")
  owner_user_id = data.get("ownerUserId") or (
      req.auth.uid if req.auth else "system_web"
  )
  center = data.get("center", {})
  letters = data.get("letters", [])
  title = data.get("title") or f"Letters near {center.get('address', 'Location')}"
  short_code = data.get("shortCode") or generate_shortcode()

  if not fanzine_id:
    raise https_fn.HttpsError(
        https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
        "'fanzineId' is required.",
    )

  db = firestore.client()
  bucket = storage.bucket()
  api_key = "AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g"

  markers_payload: List[Dict[str, Any]] = []
  if center.get("lat") is not None and center.get("lng") is not None:
    markers_payload.append({
        "lat": float(center["lat"]),
        "lng": float(center["lng"]),
        "isCenter": True,
    })

  for l in letters:
    lat = l.get("lat")
    lng = l.get("lng")
    if lat is not None and lng is not None:
      markers_payload.append({
          "lat": float(lat),
          "lng": float(lng),
          "isCenter": False,
      })

  query_parts = [
      "size=640x1024",
      "scale=2",
      "maptype=roadmap",
      f"key={api_key}",
  ]
  for m in markers_payload:
    lat = m["lat"]
    lng = m["lng"]
    is_center = m.get("isCenter", False)
    color = "0xd32f2f" if is_center else "0xea4335"
    size = "mid" if is_center else "small"
    query_parts.append(f"markers=color:{color}%7Csize:{size}%7C{lat},{lng}")

  static_map_url = (
      f"https://maps.googleapis.com/maps/api/staticmap?{'&'.join(query_parts)}"
  )
  map_img = download_remote_image(static_map_url)

  # Initialize 2000x3200 plate
  cover_canvas = Image.new(
      "RGB", (PAGE_WIDTH, PAGE_HEIGHT), color=(229, 227, 223)
  )
  if map_img:
    resized_map = map_img.resize(
        (PAGE_WIDTH, PAGE_HEIGHT), Image.Resampling.LANCZOS
    )
    cover_canvas.paste(resized_map, (0, 0))

  cover_ctx = ImageDraw.Draw(cover_canvas)
  cover_ctx.rectangle(
      [5, 5, PAGE_WIDTH - 6, PAGE_HEIGHT - 6], outline=(0, 0, 0), width=11
  )

  cover_image_id = f"map_cover_{fanzine_id}_1"
  storage_prefix = f"fanzines/{fanzine_id}"
  orig_url, list_url, grid_url = upload_three_webp_scales(
      canvas=cover_canvas,
      bucket=bucket,
      storage_prefix=storage_prefix,
      token=cover_image_id,
  )

  cover_metadata = {
      "uid": owner_user_id,
      "uploaderId": owner_user_id,
      "type": "template",
      "templateId": "map_cover",
      "title": "Map Cover",
      "isGenerated": True,
      "width": PAGE_WIDTH,
      "height": PAGE_HEIGHT,
      "aspectRatio": 0.625,
      "is5x8": True,
      "shortCode": short_code,
      "folioContext": fanzine_id,
      "usedInFanzines": [fanzine_id],
      "fileUrl": orig_url,
      "listUrl": list_url,
      "gridUrl": grid_url,
      "timestamp": firestore.SERVER_TIMESTAMP,
  }
  db.collection("images").document(cover_image_id).set(
      cover_metadata, merge=True
  )

  cover_page = {
      "id": f"{fanzine_id}_page_1",
      "pageNumber": 1,
      "imageId": cover_image_id,
      "imageUrl": orig_url,
      "gridUrl": grid_url,
      "listUrl": list_url,
      "templateId": "map_cover",
      "width": PAGE_WIDTH,
      "height": PAGE_HEIGHT,
      "is5x8": True,
      "status": "ready",
  }

  return {
      "status": "success",
      "fanzineId": fanzine_id,
      "coverPage": cover_page,
  }