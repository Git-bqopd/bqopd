import os
import time
import json
import tempfile
import re
import traceback
import base64
import firebase_admin
from firebase_admin import firestore, storage
from firebase_functions import storage_fn, https_fn, firestore_fn, options
from firebase_functions.params import SecretParam

# The new Gemini 3 SDK
from google import genai
from google.genai import types

# Initialize Firebase Admin
firebase_admin.initialize_app()

# Define Secret for Gemini API Key
GEMINI_API_KEY = SecretParam('GEMINI_API_KEY')

# --------------------------------------------------------------------------------
# HELPERS
# --------------------------------------------------------------------------------
def normalize_entity(entity_text):
    if not entity_text: return None
    clean = str(entity_text).strip()
    honorifics_pattern = r'^(Prof\.|Dr\.|Mr\.|Mrs\.|Ms\.|Miss)\s+'
    match = re.search(honorifics_pattern, clean, re.IGNORECASE)
    prefix = ""
    if match:
        prefix = match.group(0)
        clean = re.sub(honorifics_pattern, '', clean, flags=re.IGNORECASE)
    if clean.isupper() and len(clean) > 3:
        clean = clean.title()
    return {"original": entity_text, "clean": clean, "prefix": prefix}

def apply_wikilinks_locally(text, entities):
    if not text: return ""
    processed_text = text
    # Sort by length descending to avoid partial matches
    entities.sort(key=lambda x: len(x['clean']), reverse=True)

    for ent in entities:
        clean = ent['clean']
        prefix = ent['prefix']
        escaped_name = re.escape(clean)
        # Match whole words only
        pattern = re.compile(r'\b' + escaped_name + r'\b', re.IGNORECASE)
        def replace_func(match):
            return f"{prefix}[[{clean}]]"
        processed_text = pattern.sub(replace_func, processed_text)
    return processed_text

def extract_json_from_text(text):
    """
    Extracts the first valid JSON object from a string.
    Handles cases where Gemini adds conversational text around the block.
    """
    if not text: return None
    
    # Try direct load first
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Find first { and last }
    start = text.find('{')
    end = text.rfind('}')
    
    if start != -1 and end != -1:
        try:
            return json.loads(text[start:end+1])
        except json.JSONDecodeError:
            pass
            
    # Last ditch: strip markdown code blocks
    clean = text.strip()
    if clean.startswith("```json"): clean = clean[7:]
    if clean.startswith("```"): clean = clean[3:]
    if clean.endswith("```"): clean = clean[:-3]
    
    try:
        return json.loads(clean.strip())
    except:
        raise ValueError(f"Failed to extract valid JSON from response. Length: {len(text)}")

# --------------------------------------------------------------------------------
# TRAFFIC CONTROL MANAGER
# --------------------------------------------------------------------------------
# CHANGED: Switched to on_document_written to catch Creations as well as Updates
@firestore_fn.on_document_written(document="fanzines/{fanzineId}", memory=1024, timeout_sec=540)
def fanzine_traffic_manager(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    """
    Orchestrates the high-level state of a fanzine.
    """
    # If document was deleted, do nothing
    if not event.data.after or not event.data.after.exists: return

    data = event.data.after.to_dict()
    fanzine_id = event.params['fanzineId']
    db = firestore.client()
    fref = db.collection('fanzines').document(fanzine_id)
    status = data.get('processingStatus', 'idle')

    # STEP 1: Ingest PDF
    if status == 'needs_ingest':
        fref.update({'processingStatus': 'extracting_images'})
        _do_pdf_ingest(fanzine_id, data.get('sourceFile'))
        return

    # STEP 2: Monitor OCR Progress
    if status == 'processing_ocr':
        # Check if all pages are complete (no 'ready' or 'queued' pages left)
        pages_ref = fref.collection('pages')
        pending_docs = list(pages_ref.where(filter=firestore.FieldFilter('status', 'in', ['ready', 'queued'])).limit(1).stream())

        if not pending_docs:
            fref.update({'processingStatus': 'review_needed'})
        return

    # STEP 3: Review Completion
    if status == 'review_needed':
        # Check if all pages are marked 'complete'
        pages_ref = fref.collection('pages')
        # We check for any page that is NOT complete. 
        # Since != might require specific indexes, we check for known non-complete statuses.
        # Note: 'ocr_complete' is deprecated but included for backward compatibility if any exist.
        non_complete_statuses = ['review_needed', 'error', 'ready', 'queued', 'ocr_complete']
        pending_review = list(pages_ref.where(filter=firestore.FieldFilter('status', 'in', non_complete_statuses)).limit(1).stream())
        
        if not pending_review:
            fref.update({'processingStatus': 'ready_for_agg'})
        return

    # STEP 4: Aggregation
    if status == 'ready_for_agg':
        fref.update({'processingStatus': 'aggregating'})
        _do_aggregation(fanzine_id)
        return

# --------------------------------------------------------------------------------
# GEMINI 3 FLASH OCR WORKER
# --------------------------------------------------------------------------------
@firestore_fn.on_document_written(document="fanzines/{fanzineId}/pages/{pageId}", secrets=[GEMINI_API_KEY], memory=2048, timeout_sec=120)
def ocr_worker(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    """
    Triggered when a page status is set to 'queued'.
    Performs OCR using Gemini 3 Flash.
    """
    if not event.data.after: return
    data = event.data.after.to_dict()

    # Only run if explicitly queued
    if data.get('status') != 'queued': return

    fanzine_id = event.params['fanzineId']
    page_id = event.params['pageId']
    db = firestore.client()
    fref = db.collection('fanzines').document(fanzine_id)
    page_ref = event.data.after.reference

    try:
        bucket = storage.bucket()
        blob = bucket.blob(data.get('storagePath'))
        image_bytes = blob.download_as_bytes()

        # Initialize the Google Gen AI SDK Client
        client = genai.Client(api_key=GEMINI_API_KEY.value)

        prompt = """
        ACT AS AN ARCHIVIST. Perform a deep spatial OCR on this fanzine page for archival and indexing purposes.
        This is historical content for inclusion in a community-driven database.
        1. Extract all text, maintaining the reading order of multi-column layouts and floating boxes.
        2. Identify and extract names of people, groups, and entities mentioned.
        3. Output strictly as JSON with this structure:
           {"text": "full extracted markdown text", "entities": ["Name 1", "Name 2"]}
        Do not truncate, summarize, or omit any text from the page. If the page is long, provide the full transcription.
        """

        # Define safety settings to be less restrictive for OCR of archival docs
        safety_settings = [
            types.SafetySetting(category="HARM_CATEGORY_HATE_SPEECH", threshold="BLOCK_NONE"),
            types.SafetySetting(category="HARM_CATEGORY_DANGEROUS_CONTENT", threshold="BLOCK_NONE"),
            types.SafetySetting(category="HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold="BLOCK_NONE"),
            types.SafetySetting(category="HARM_CATEGORY_HARASSMENT", threshold="BLOCK_NONE"),
        ]

        # Using Gemini 3 Flash Preview as requested
        # WRAPPING IN RETRY LOGIC FOR RECITATION ERRORS
        model_name = "gemini-3-flash-preview"
        try:
            response = client.models.generate_content(
                model=model_name,
                contents=[
                    prompt,
                    types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    safety_settings=safety_settings
                )
            )
            
            # Check for RECITATION stop reason specifically
            # Convert to string to handle Enum values like FinishReason.RECITATION
            finish_reason_str = str(response.candidates[0].finish_reason) if response.candidates else ""
            if "RECITATION" in finish_reason_str:
                raise ValueError(f"FinishReason.RECITATION found in {model_name}")
                
        except Exception as e:
            if "RECITATION" in str(e):
                print(f"Gemini 3 Flash hit RECITATION. Falling back to Gemini 1.5 Pro...")
                model_name = "gemini-1.5-pro"
                response = client.models.generate_content(
                    model=model_name,
                    contents=[
                        prompt,
                        types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")
                    ],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        safety_settings=safety_settings
                    )
                )
            else:
                raise e

        # Handle potential empty or null response text
        if not response.text:
            # Enhanced error logging for citation/safety blocks
            finish_reason = "Unknown"
            if response.candidates:
                finish_reason = response.candidates[0].finish_reason
            raise ValueError(f"Gemini returned empty response. Finish reason: {finish_reason}")

        res_json = extract_json_from_text(response.text)

        raw_text = res_json.get('text', '')

        ents = []
        entity_id_errors = 0
        for e_name in res_json.get('entities', []):
            norm = normalize_entity(e_name)
            if norm: ents.append(norm)
            else: entity_id_errors += 1

        processed = apply_wikilinks_locally(raw_text, ents)

        page_ref.update({
            'text_raw': raw_text,
            'text_processed': processed,
            'detected_entities': [e['clean'] for e in ents],
            'status': 'review_needed',
            'error_entity_id': entity_id_errors,
            'processedAt': firestore.SERVER_TIMESTAMP,
            'ocrModelUsed': model_name
        })

        # Pulse the parent to check if all pages are done
        fref.update({'lastWorkerPulse': firestore.SERVER_TIMESTAMP})

    except Exception as e:
        print(f"OCR Worker Crash on {fanzine_id}/{page_id}: {traceback.format_exc()}")
        page_ref.update({'status': 'error', 'errorLog': str(e)})
        # Pulse parent to ensure it doesn't get stuck waiting
        fref.update({'lastWorkerPulse': firestore.SERVER_TIMESTAMP})

# --------------------------------------------------------------------------------
# CALLABLES (Manual Triggers for Workbench)
# --------------------------------------------------------------------------------

@https_fn.on_call()
def trigger_batch_ocr(req: https_fn.CallableRequest):
    """
    Manually triggers OCR for all 'ready' or 'error' pages in a fanzine.
    Updates Fanzine status to 'processing_ocr'.
    """
    fid = req.data.get('fanzineId')
    print(f"--- trigger_batch_ocr CALLED for fid: {fid} ---")
    if not fid: 
        print("Error: Missing fanzineId")
        return {"error": "Missing fanzineId"}

    db = firestore.client()
    fref = db.collection('fanzines').document(fid)

    # Update parent status
    fref.update({'processingStatus': 'processing_ocr'})

    # Batch update pages
    pages = fref.collection('pages').stream()
    batch = db.batch()
    count = 0
    updated = 0

    for p in pages:
        p_data = p.to_dict()
        status = p_data.get('status')
        # Retry 'error' pages or start 'ready' pages
        if status in ['ready', 'error']:
            print(f"Queuing page {p_data.get('pageNumber')} (current status: {status})")
            # Resetting status to 'queued' triggers the ocr_worker function above
            batch.update(p.reference, {'status': 'queued', 'errorLog': firestore.DELETE_FIELD})
            updated += 1
            count += 1

        # Firestore batch limit is 500
        if count >= 400:
            print(f"Committing batch of {count}...")
            batch.commit()
            batch = db.batch()
            count = 0

    if count > 0:
        print(f"Committing final batch of {count}...")
        batch.commit()

    print(f"Successfully queued {updated} pages for {fid}")
    return {"success": True, "queued_count": updated}

@https_fn.on_call()
def finalize_fanzine_data(req: https_fn.CallableRequest):
    """
    Manually triggers aggregation.
    """
    fid = req.data.get('fanzineId')
    if not fid: return {"error": "Missing fanzineId"}

    _do_aggregation(fid)

    # Fetch result stats
    db = firestore.client()
    fref = db.collection('fanzines').document(fid)
    doc = fref.get()
    ent_count = 0
    if doc.exists:
        ent_count = len(doc.to_dict().get('draftEntities', []))

    return {"success": True, "entity_count": ent_count}

@https_fn.on_call()
def rescan_fanzine(req: https_fn.CallableRequest):
    fid = req.data.get('fanzineId')
    # Force update by adding a timestamp; otherwise if status is already 'needs_ingest',
    # Firestore won't trigger the on_update function.
    firestore.client().collection('fanzines').document(fid).update({
        'processingStatus': 'needs_ingest',
        'lastRescanRequest': firestore.SERVER_TIMESTAMP
    })
    return {"success": True}

@https_fn.on_call()
def delete_fanzine(req: https_fn.CallableRequest):
    fid = req.data.get('fanzineId')
    db, bucket = firestore.client(), storage.bucket()
    fref = db.collection('fanzines').document(fid)

    # Delete pages subcollection
    for p in fref.collection('pages').stream():
        p.reference.delete()

    # Delete storage
    blobs = bucket.list_blobs(prefix=f"fanzines/{fid}/")
    for b in blobs:
        b.delete()

    fref.delete()
    return {"success": True}

# --------------------------------------------------------------------------------
# PDF INGEST & AGGREGATION
# --------------------------------------------------------------------------------
def _do_pdf_ingest(fanzine_id, file_path):
    import pypdfium2 as pdfium
    db = firestore.client()
    bucket = storage.bucket()
    fref = db.collection('fanzines').document(fanzine_id)
    try:
        blob = bucket.blob(file_path)
        if not blob.exists(): raise Exception("Source PDF missing.")

        local_pdf = os.path.join(tempfile.gettempdir(), f"{fanzine_id}.pdf")
        blob.download_to_filename(local_pdf)

        pdf = pdfium.PdfDocument(local_pdf)
        n_pages = len(pdf)

        # Clear existing pages if re-ingesting
        old_pages = fref.collection('pages').stream()
        for p in old_pages: p.reference.delete()

        batch = db.batch()
        batch_count = 0

        for i in range(n_pages):
            page_num = i + 1
            # Render at higher scale for better OCR accuracy
            pil_img = pdf[i].render(scale=2.0).to_pil()
            local_img = os.path.join(tempfile.gettempdir(), f"ingest_{fanzine_id}_{page_num}.jpg")
            pil_img.save(local_img, 'JPEG', quality=85)

            dest = f"fanzines/{fanzine_id}/pages/page_{page_num:03d}.jpg"
            new_blob = bucket.blob(dest)
            new_blob.upload_from_filename(local_img)

            # Setup image data
            # Use signed URL with 1 hour expiration as initial value
            # Frontend handles refreshing this URL if expired
            img_ref = fref.collection('pages').document()
            batch.set(img_ref, {
                'pageNumber': page_num,
                'storagePath': dest,
                'imageUrl': new_blob.public_url if new_blob.public_url else new_blob.generate_signed_url(expiration=3600),
                'status': 'ready',
                'uploadedAt': firestore.SERVER_TIMESTAMP
            })

            batch_count += 1
            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0

            if os.path.exists(local_img): os.remove(local_img)

        if batch_count > 0:
            batch.commit()

        fref.update({'processingStatus': 'images_ready', 'pageCount': n_pages})

    except Exception as e:
        print(f"Ingest Error: {e}")
        fref.update({'processingStatus': 'error', 'error_ingest': str(e)})

def _do_aggregation(fanzine_id):
    db = firestore.client()
    fref = db.collection('fanzines').document(fanzine_id)
    try:
        all_ents = set()
        pages = fref.collection('pages').stream()

        # Aggregate entities
        for p in pages:
            d = p.to_dict()
            for e in d.get('detected_entities', []):
                all_ents.add(e)

        # Update main doc
        fref.update({
            'draftEntities': list(all_ents),
            'processingStatus': 'complete',
            'aggregatedAt': firestore.SERVER_TIMESTAMP
        })
    except Exception as e:
        fref.update({'processingStatus': 'error', 'error_agg': str(e)})

# --------------------------------------------------------------------------------
# UPLOAD TRIGGER
# --------------------------------------------------------------------------------
@storage_fn.on_object_finalized()
def handle_pdf_upload(event: storage_fn.CloudEvent[storage_fn.StorageObjectData]):
    file_path = event.data.name
    # Only process PDFs in the raw folder
    if not file_path.endswith('.pdf') or 'uploads/raw_pdfs/' not in file_path: return

    db = firestore.client()

    # Create the fanzine shell
    # ADDED: status='draft' so it appears in the dashboard
    _, ref = db.collection('fanzines').add({
        'title': os.path.basename(file_path).replace('.pdf', '').replace('_', ' ').title(),
        'sourceFile': file_path,
        'processingStatus': 'needs_ingest',
        'status': 'draft',
        'creationDate': firestore.SERVER_TIMESTAMP,
        'uploaderId': event.data.metadata.get('uploaderId') if event.data.metadata else 'unknown'
    })

    print(f"Created fanzine {ref.id} for {file_path}")

# --------------------------------------------------------------------------------
# GRAPH SYNC TRIGGERS
# --------------------------------------------------------------------------------

def prepare_graph_payload(source_id, target_id, relationship_type, timestamp, metadata=None):
    """
    Sanitizes and prepares a JSON payload for external graph sync.
    """
    if metadata is None: metadata = {}
    
    # Convert timestamp to milliseconds if it's a Firestore Timestamp
    created_at_ms = int(time.time() * 1000)
    if hasattr(timestamp, 'timestamp'):
        created_at_ms = int(timestamp.timestamp() * 1000)
    elif isinstance(timestamp, int):
        created_at_ms = timestamp

    payload = {
        "source": source_id,
        "target": target_id,
        "type": relationship_type,
        "createdAt": created_at_ms
    }
    payload.update(metadata)
    return payload

@firestore_fn.on_document_created(document="Users/{userId}/following/{targetUserId}")
def on_follow_user(event: firestore_fn.Event[firestore_fn.DocumentSnapshot]) -> None:
    """
    Triggered when a user follows another user.
    """
    user_id = event.params['userId']
    target_user_id = event.params['targetUserId']
    
    data = event.data.to_dict() if event.data else {}
    timestamp = data.get('createdAt', firestore.SERVER_TIMESTAMP)

    payload = prepare_graph_payload(user_id, target_user_id, "FOLLOWS", timestamp)
    
    print(f"Graph Sync [FOLLOW]: {json.dumps(payload)}")
    # TODO: Push to Neo4j

@firestore_fn.on_document_created(document="Likes/{likeId}")
def on_like_content(event: firestore_fn.Event[firestore_fn.DocumentSnapshot]) -> None:
    """
    Triggered when content is liked.
    """
    data = event.data.to_dict() if event.data else {}
    user_id = data.get('userId')
    content_id = data.get('contentId')
    
    if not user_id or not content_id:
        print(f"Invalid Like document: {event.params['likeId']}")
        return

    timestamp = data.get('createdAt', firestore.SERVER_TIMESTAMP)
    payload = prepare_graph_payload(user_id, content_id, "LIKES", timestamp)

    print(f"Graph Sync [LIKE]: {json.dumps(payload)}")
    # TODO: Push to Neo4j

@firestore_fn.on_document_created(document="Remixes/{remixId}")
def on_remix_content(event: firestore_fn.Event[firestore_fn.DocumentSnapshot]) -> None:
    """
    Triggered when content is remixed.
    """
    data = event.data.to_dict() if event.data else {}
    user_id = data.get('userId') # The remixer
    original_content_id = data.get('originalContentId')
    
    if not user_id or not original_content_id:
        print(f"Invalid Remix document: {event.params['remixId']}")
        return

    timestamp = data.get('createdAt', firestore.SERVER_TIMESTAMP)
    payload = prepare_graph_payload(user_id, original_content_id, "REMIXED", timestamp, {
        "remixContentId": event.params['remixId']
    })

    print(f"Graph Sync [REMIX]: {json.dumps(payload)}")
    # TODO: Push to Neo4j