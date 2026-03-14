import os
import time
import json
import tempfile
import re
import traceback
import firebase_admin
from firebase_admin import firestore, storage
from firebase_functions import storage_fn, https_fn, firestore_fn
from firebase_functions.params import SecretParam

# The new Google Gen AI SDK
from google import genai
from google.genai import types

# Google Cloud Vision for bulletproof OCR
from google.cloud import vision

# Initialize Firebase Admin
firebase_admin.initialize_app()

# Define Secret for Gemini API Key (Only used for Entity Extraction now)
GEMINI_API_KEY = SecretParam('GEMINI_API_KEY')

# --------------------------------------------------------------------------------
# HELPERS
# --------------------------------------------------------------------------------
def normalize_entity(entity_text):
    if not entity_text: return None
    clean = str(entity_text).strip()
    if clean.isupper() and len(clean) > 3:
        clean = clean.title()
    return clean

def apply_wikilinks_locally(text, entities):
    if not text or not entities: return text or ""
    processed_text = text
    entities.sort(key=lambda x: len(x) if isinstance(x, str) else 0, reverse=True)
    for ent in entities:
        if not ent: continue
        escaped_name = re.escape(ent)
        pattern = re.compile(r'\b' + escaped_name + r'\b', re.IGNORECASE)
        processed_text = pattern.sub(f"[[{ent}]]", processed_text)
    return processed_text

def extract_json_from_text(text):
    if not text: return None
    try: return json.loads(text)
    except json.JSONDecodeError: pass

    start = text.find('[') if text.strip().startswith('[') else text.find('{')
    end = text.rfind(']') if text.strip().startswith('[') else text.rfind('}')
    if start != -1 and end != -1:
        try: return json.loads(text[start:end+1])
        except json.JSONDecodeError: pass

    clean = text.strip()
    bt = "`" * 3
    if clean.startswith(bt + "json"): clean = clean[7:]
    if clean.startswith(bt): clean = clean[3:]
    if clean.endswith(bt): clean = clean[:-3]

    try: return json.loads(clean.strip())
    except: raise ValueError("Failed to extract valid JSON from response.")

def generate_simple_shortcode():
    import random
    import string
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=7))

# --------------------------------------------------------------------------------
# TRAFFIC CONTROL MANAGER
# --------------------------------------------------------------------------------
@firestore_fn.on_document_written(document="fanzines/{fanzineId}", memory=1024, timeout_sec=540)
def fanzine_traffic_manager(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    if not event.data.after or not event.data.after.exists: return
    data = event.data.after.to_dict()
    fanzine_id = event.params['fanzineId']
    db = firestore.client()
    fref = db.collection('fanzines').document(fanzine_id)
    status = data.get('processingStatus', 'idle')

    if status == 'needs_ingest':
        fref.update({'processingStatus': 'extracting_images'})
        _do_pdf_ingest(fanzine_id, data.get('sourceFile'))
    elif status == 'processing_ocr':
        pages_ref = fref.collection('pages')
        pending = list(pages_ref.where(filter=firestore.FieldFilter('status', 'in', ['ready', 'queued'])).limit(1).stream())
        if not pending:
            fref.update({'processingStatus': 'review_needed'})
    elif status == 'ready_for_agg':
        fref.update({'processingStatus': 'aggregating'})
        _do_aggregation(fanzine_id)

# --------------------------------------------------------------------------------
# WORKER 1: TRANSCRIPTION (Image -> Text via Google Cloud Vision)
# --------------------------------------------------------------------------------
@firestore_fn.on_document_written(document="fanzines/{fanzineId}/pages/{pageId}", memory=1024, timeout_sec=120)
def ocr_worker(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    if not event.data.after: return
    data = event.data.after.to_dict()
    if data.get('status') != 'queued': return

    db = firestore.client()
    page_ref = event.data.after.reference

    try:
        vision_client = vision.ImageAnnotatorClient()
        image = vision.Image()

        storage_path = data.get('storagePath')
        if storage_path:
            bucket_name = storage.bucket().name
            image.source.image_uri = f"gs://{bucket_name}/{storage_path}"
        else:
            image_url = data.get('imageUrl')
            if not image_url: raise ValueError("No image source available for Vision API.")
            import urllib.request
            req = urllib.request.Request(image_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req) as res: image_bytes = res.read()
            image.content = image_bytes

        response = vision_client.document_text_detection(image=image)

        if response.error.message:
            raise Exception(f"Vision API Error: {response.error.message}")

        if response.full_text_annotation:
            transcription = response.full_text_annotation.text
        else:
            transcription = "[No text detected on this page]"

        image_id = data.get('imageId')
        if not image_id:
            new_img_ref = db.collection('images').document()
            image_id = new_img_ref.id
            new_img_ref.set({
                'storagePath': storage_path,
                'fileUrl': data.get('imageUrl', ''),
                'shortCode': generate_simple_shortcode(),
                'status': 'approved',
                'timestamp': firestore.SERVER_TIMESTAMP,
                'uploaderId': data.get('uploaderId', 'system_ingest'),
                'text': transcription,
                'text_raw': transcription
            })
            page_ref.update({'imageId': image_id})
        else:
            db.collection('images').document(image_id).update({
                'text': transcription,
                'text_raw': transcription
            })

        page_ref.update({
            'text_raw': transcription,
            'status': 'transcribed',
            'processedAt': firestore.SERVER_TIMESTAMP,
            'ocrModelUsed': 'Google Cloud Vision'
        })

    except Exception as e:
        print(f"Transcription Error: {traceback.format_exc()}")
        page_ref.update({'status': 'error', 'errorLog': f"Transcription: {str(e)}"})


# --------------------------------------------------------------------------------
# WORKER 2: ENTITY EXTRACTION (Text -> Entities via Gemini)
# --------------------------------------------------------------------------------
@firestore_fn.on_document_written(document="fanzines/{fanzineId}/pages/{pageId}", secrets=[GEMINI_API_KEY], memory=1024, timeout_sec=60)
def entity_worker(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    if not event.data.after: return
    data = event.data.after.to_dict()
    if data.get('status') != 'entity_queued': return

    db = firestore.client()
    page_ref = event.data.after.reference
    text_content = data.get('text_raw', '')

    if not text_content or text_content == "[No text detected on this page]":
        page_ref.update({'status': 'complete', 'detected_entities': []})
        return

    try:
        client = genai.Client(api_key=GEMINI_API_KEY.value)
        prompt = f"Identify people and groups in this text. Return a JSON array of strings: {text_content}"

        model_name = "gemini-3-flash-preview"
        try:
            response = client.models.generate_content(
                model=model_name,
                contents=[prompt],
                config=types.GenerateContentConfig(response_mime_type="application/json")
            )
        except Exception as e:
            print(f"Primary entity model {model_name} failed: {str(e)}. Falling back to Pro...")
            model_name = "gemini-3.1-pro-preview"
            response = client.models.generate_content(
                model=model_name,
                contents=[prompt],
                config=types.GenerateContentConfig(response_mime_type="application/json")
            )

        ents = extract_json_from_text(response.text)
        if not isinstance(ents, list): ents = []
        clean_ents = [normalize_entity(e) for e in ents if normalize_entity(e)]

        image_id = data.get('imageId')
        if image_id:
            db.collection('images').document(image_id).update({'detected_entities': clean_ents})

        page_ref.update({
            'detected_entities': clean_ents,
            'status': 'complete',
            'entitiesProcessedAt': firestore.SERVER_TIMESTAMP,
            'entityModelUsed': model_name
        })

    except Exception as e:
        print(f"Entity Extraction Error: {traceback.format_exc()}")
        page_ref.update({'status': 'error', 'errorLog': f"Entities: {str(e)}"})

# --------------------------------------------------------------------------------
# CALLABLES & PDF PROCESSING (Now with Payload Armor & Error Snitching)
# --------------------------------------------------------------------------------

@https_fn.on_call()
def trigger_batch_ocr(req: https_fn.CallableRequest):
    try:
        fid = req.data.get('fanzineId') if isinstance(req.data, dict) else req.data
        if not fid or not isinstance(fid, str): raise ValueError("Invalid or missing fanzineId")

        db = firestore.client()
        db.collection('fanzines').document(fid).update({'processingStatus': 'processing_ocr'})
        pages = db.collection('fanzines').document(fid).collection('pages').stream()
        batch, count = db.batch(), 0
        for p in pages:
            data = p.to_dict() or {}
            if data.get('status') in ['ready', 'error', 'transcribed']:
                batch.update(p.reference, {'status': 'queued', 'errorLog': firestore.DELETE_FIELD})
                count += 1
            if count >= 400:
                batch.commit()
                batch = db.batch()
                count = 0
        if count > 0: batch.commit()
        return {"success": True, "count": count}
    except Exception as e:
        print(f"OCR Callable Error: {traceback.format_exc()}")
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INTERNAL, message=str(e))

@https_fn.on_call()
def trigger_batch_entities(req: https_fn.CallableRequest):
    try:
        fid = req.data.get('fanzineId') if isinstance(req.data, dict) else req.data
        if not fid or not isinstance(fid, str): raise ValueError("Invalid or missing fanzineId")

        db = firestore.client()
        pages = db.collection('fanzines').document(fid).collection('pages').stream()
        batch, count = db.batch(), 0
        for p in pages:
            data = p.to_dict() or {}
            if data.get('status') == 'transcribed':
                batch.update(p.reference, {'status': 'entity_queued', 'errorLog': firestore.DELETE_FIELD})
                count += 1
            if count >= 400:
                batch.commit()
                batch = db.batch()
                count = 0
        if count > 0: batch.commit()
        return {"success": True, "count": count}
    except Exception as e:
        print(f"Entities Callable Error: {traceback.format_exc()}")
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INTERNAL, message=str(e))

@https_fn.on_call()
def finalize_fanzine_data(req: https_fn.CallableRequest):
    try:
        fid = req.data.get('fanzineId') if isinstance(req.data, dict) else req.data
        _do_aggregation(fid)
        return {"success": True}
    except Exception as e:
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INTERNAL, message=str(e))

@https_fn.on_call()
def rescan_fanzine(req: https_fn.CallableRequest):
    try:
        fid = req.data.get('fanzineId') if isinstance(req.data, dict) else req.data
        firestore.client().collection('fanzines').document(fid).update({
            'processingStatus': 'needs_ingest',
            'lastRescanRequest': firestore.SERVER_TIMESTAMP
        })
        return {"success": True}
    except Exception as e:
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INTERNAL, message=str(e))

@https_fn.on_call()
def delete_fanzine(req: https_fn.CallableRequest):
    try:
        fid = req.data.get('fanzineId') if isinstance(req.data, dict) else req.data
        db, bucket = firestore.client(), storage.bucket()
        fref = db.collection('fanzines').document(fid)
        for p in fref.collection('pages').stream(): p.reference.delete()
        blobs = bucket.list_blobs(prefix=f"fanzines/{fid}/")
        for b in blobs: b.delete()
        fref.delete()
        return {"success": True}
    except Exception as e:
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INTERNAL, message=str(e))

def _do_pdf_ingest(fanzine_id, file_path):
    import fitz  # PyMuPDF
    db = firestore.client()
    bucket = storage.bucket()
    fref = db.collection('fanzines').document(fanzine_id)

    try:
        blob = bucket.blob(file_path)
        if not blob.exists():
            raise Exception("Source PDF missing from Cloud Storage.")

        pdf_bytes = blob.download_as_bytes()
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        n_pages = len(doc)

        for p in fref.collection('pages').stream():
            p.reference.delete()

        batch = db.batch()
        batch_count = 0

        for i in range(n_pages):
            page_num = i + 1
            page = doc.load_page(i)
            mat = fitz.Matrix(2.0, 2.0)
            pix = page.get_pixmap(matrix=mat, alpha=False)
            img_bytes = pix.tobytes("jpeg")

            dest = f"fanzines/{fanzine_id}/pages/page_{page_num:03d}.jpg"
            new_blob = bucket.blob(dest)
            new_blob.upload_from_string(img_bytes, content_type="image/jpeg")

            batch.set(fref.collection('pages').document(), {
                'pageNumber': page_num,
                'storagePath': dest,
                'imageUrl': '',
                'status': 'ready',
                'uploadedAt': firestore.SERVER_TIMESTAMP
            })

            batch_count += 1
            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0

            page = None
            pix = None

        if batch_count > 0:
            batch.commit()

        doc.close()
        fref.update({'processingStatus': 'images_ready', 'pageCount': n_pages})

    except Exception as e:
        print(f"Ingest Error: {traceback.format_exc()}")
        fref.update({'processingStatus': 'error', 'error_ingest': str(e)})

def _do_aggregation(fanzine_id):
    db = firestore.client()
    fref = db.collection('fanzines').document(fanzine_id)
    try:
        all_ents, creators, seen_c, indicia = set(), [], set(), []
        pages = fref.collection('pages').order_by('pageNumber').stream()
        for p in pages:
            d = p.to_dict()
            for e in d.get('detected_entities', []): all_ents.add(e)
            if d.get('imageId'):
                img = db.collection('images').document(d['imageId']).get().to_dict()
                if img:
                    if img.get('indicia'): indicia.append(img['indicia'])
                    for c in img.get('creators', []):
                        k = f"{c.get('uid')}_{c.get('role')}" if c.get('uid') else f"{c.get('name')}_{c.get('role')}"
                        if k not in seen_c: seen_c.add(k); creators.append(c)
        fref.update({
            'draftEntities': list(all_ents),
            'masterCreators': creators,
            'masterIndicia': "\n\n".join(indicia),
            'processingStatus': 'complete',
            'aggregatedAt': firestore.SERVER_TIMESTAMP,
            'status': 'working'
        })
    except Exception as e:
        fref.update({'processingStatus': 'error', 'error_agg': str(e)})

@storage_fn.on_object_finalized()
def handle_pdf_upload(event: storage_fn.CloudEvent[storage_fn.StorageObjectData]):
    file_path = event.data.name
    if not file_path.endswith('.pdf') or 'uploads/raw_pdfs/' not in file_path: return
    db = firestore.client()
    db.collection('fanzines').add({
        'title': os.path.basename(file_path).replace('.pdf', '').replace('_', ' ').title(),
        'sourceFile': file_path,
        'processingStatus': 'needs_ingest',
        'status': 'draft',
        'creationDate': firestore.SERVER_TIMESTAMP,
        'uploaderId': event.data.metadata.get('uploaderId') if event.data.metadata else 'unknown'
    })