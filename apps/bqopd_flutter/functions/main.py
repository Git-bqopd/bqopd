import os
import time
import json
import tempfile
import re
import traceback
import urllib.request
import urllib.parse
from io import BytesIO
from PIL import Image

import firebase_admin
from firebase_admin import firestore, storage
from firebase_functions import storage_fn, https_fn, firestore_fn
from firebase_functions.params import SecretParam
from google import genai
from google.genai import types
from google.cloud import vision

# Initialize Firebase Admin
firebase_admin.initialize_app()

# Define Secret for Gemini API Key
GEMINI_API_KEY = SecretParam('GEMINI_API_KEY')

def normalize_entity(entity_text):
    if not entity_text: return None
    clean = str(entity_text).strip()
    if clean.isupper() and len(clean) > 3:
        clean = clean.title()
    return clean

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

def ensure_shortcode(db, collection_name, document_id, content_type):
    doc_ref = db.collection(collection_name).document(document_id)
    doc_snapshot = doc_ref.get()
    if not doc_snapshot.exists:
        return None
    data = doc_snapshot.to_dict()
    if data.get('shortCode'):
        return data.get('shortCode')
    is_unique = False
    short_code = ""
    while not is_unique:
        short_code = generate_simple_shortcode()
        sc_ref = db.collection('shortcodes').document(short_code.upper())
        if not sc_ref.get().exists:
            is_unique = True
            sc_ref.set({
                'type': content_type,
                'contentId': document_id,
                'displayCode': short_code,
                'createdAt': firestore.SERVER_TIMESTAMP
            })
    doc_ref.update({
        'shortCode': short_code,
        'shortCodeKey': short_code.upper()
    })
    return short_code

@firestore_fn.on_document_written(document="fanzines/{fanzineId}", memory=256, timeout_sec=540)
def fanzine_traffic_manager(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    if not event.data.after or not event.data.after.exists: return
    data = event.data.after.to_dict()
    fanzine_id = event.params['fanzineId']
    db = firestore.client()
    fref = db.collection('fanzines').document(fanzine_id)
    if not data.get('shortCode'):
        ensure_shortcode(db, 'fanzines', fanzine_id, 'fanzine')
        return
    status = data.get('processingStatus', 'idle')
    if status == 'needs_ingest':
        fref.update({'processingStatus': 'extracting_images'})
        _do_pdf_ingest(fanzine_id, data.get('sourceFile'), data.get('uploaderId', 'system_ingest'))
    elif status == 'images_ready':
        fref.update({'processingStatus': 'processing_ocr'})
        pages = fref.collection('pages').stream()
        batch = db.batch()
        for p in pages:
            batch.update(p.reference, {'status': 'queued'})
        batch.commit()

@firestore_fn.on_document_written(document="fanzines/{fanzineId}/pages/{pageId}", memory=512, timeout_sec=120)
def ocr_worker(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    if not event.data.after: return
    data = event.data.after.to_dict()
    if data.get('status') != 'queued': return
    db = firestore.client()
    page_ref = event.data.after.reference
    fanzine_id = event.params['fanzineId']
    image_id = data.get('imageId')
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
             req = urllib.request.Request(image_url, headers={'User-Agent': 'Mozilla/5.0'})
             with urllib.request.urlopen(req) as res: image_bytes = res.read()
             image.content = image_bytes
         response = vision_client.document_text_detection(image=image)
         if response.error.message:
             raise Exception(f"Vision API Error: {response.error.message}")
         transcription = response.full_text_annotation.text if response.full_text_annotation else "[No text detected]"
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
                 'text_raw': transcription,
                 'needs_ai_cleaning': True,
                 'folioContext': fanzine_id,
                 'usedInFanzines': [fanzine_id]
             })
             page_ref.update({'imageId': image_id})
         else:
             db.collection('images').document(image_id).update({
                 'text_raw': transcription,
                 'needs_ai_cleaning': True
             })
         page_ref.update({
             'status': 'transcribed',
             'processedAt': firestore.SERVER_TIMESTAMP
         })
    except Exception as e:
         print(f"Transcription Error: {traceback.format_exc()}")
         page_ref.update({'status': 'error', 'errorLog': f"Transcription: {str(e)}"})

@firestore_fn.on_document_written(document="images/{imageId}", secrets=[GEMINI_API_KEY], memory=512, timeout_sec=120)
def ai_cleaning_worker(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    if not event.data.after or not event.data.after.exists: return
    data = event.data.after.to_dict()
    if not data.get('needs_ai_cleaning'): return
    text_raw = data.get('text_raw', '')
    db = firestore.client()
    if not text_raw or text_raw == "[No text detected]":
        event.data.after.reference.update({
            'needs_ai_cleaning': False,
            'text_corrected': text_raw,
            'text_corrected_ai': text_raw,
            'text_linked': text_raw,
            'needs_linking': False
        })
        return
    try:
        client = genai.Client(api_key=GEMINI_API_KEY.value)
        # Step A: Perform Formatting, Typos fix & Cleaning
        prompt_clean = f"Clean up the following raw OCR text from a fanzine. Fix typos, standardize headers, and format it properly as markdown. Do not add conversational filler. Output only the cleaned text.\n\nText:\n{text_raw}"
        response_clean = client.models.generate_content(
            model="gemini-3.7-flash",
            contents=[prompt_clean],
        )
        clean_text = response_clean.text.strip()
        # Step B: Perform Entity Extraction
        prompt_ents = f"Identify people, groups, or entities in this text. Return a JSON array of strings containing their names exactly as they appear in the text: {clean_text}"
        response_ents = client.models.generate_content(
            model="gemini-3.7-flash",
            contents=[prompt_ents],
            config=types.GenerateContentConfig(response_mime_type="application/json")
        )
        ents = extract_json_from_text(response_ents.text)
        clean_ents = [normalize_entity(e) for e in ents if normalize_entity(e)] if isinstance(ents, list) else []
        # Step C: Programmatically align brackets [[wikilinks]] based on database usernames
        text_linked = clean_text
        clean_ents.sort(key=lambda x: len(x), reverse=True)
        for ent in clean_ents:
            if not ent: continue
            handle = ent.lower().replace(' ', '-')
            handle = re.sub(r'[^a-z0-9-]', '', handle)
            user_doc = db.collection('usernames').document(handle).get()
            replacement = f"[[{ent}]]"
            if user_doc.exists:
                u_data = user_doc.to_dict()
                if 'redirect' in u_data:
                    target_handle = u_data['redirect']
                    target_doc = db.collection('usernames').document(target_handle).get()
                    if target_doc.exists:
                        target_uid = target_doc.to_dict().get('uid')
                        if target_uid: replacement = f"[[{ent}|user:{target_uid}]]"
                elif 'uid' in u_data:
                    replacement = f"[[{ent}|user:{u_data['uid']}]]"
            escaped_name = re.escape(ent)
            pattern = re.compile(r'(?<!\[)(' + escaped_name + r')(?!\])', re.IGNORECASE)
            text_linked = pattern.sub(replacement, text_linked)
        # Step D: Save the final unified output to spelling, baseline, and link fields
        event.data.after.reference.update({
            'text_corrected': text_linked,
            'text_corrected_ai': text_linked,
            'text_linked': text_linked,
            'detected_entities': clean_ents,
            'needs_ai_cleaning': False,
            'needs_linking': False
        })
        # Bubble up extracted entities to the parent Fanzines
        used_in = data.get('usedInFanzines', [])
        if clean_ents and used_in:
            for fid in used_in:
                db.collection('fanzines').document(fid).update({
                    'draftEntities': firestore.ArrayUnion(clean_ents)
                })
    except Exception as e:
        print(f"AI Pipeline Error: {traceback.format_exc()}")
        event.data.after.reference.update({
            'errorLog_cleaning': str(e),
            'needs_ai_cleaning': False,
            'needs_linking': False
        })

@firestore_fn.on_document_written(document="images/{imageId}", memory=512, timeout_sec=120)
def generate_thumbnails(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    if not event.data.after or not event.data.after.exists: return
    data = event.data.after.to_dict()
    file_url = data.get('fileUrl')
    storage_path = data.get('storagePath')
    if not file_url and not storage_path: return
    if data.get('gridUrl') and data.get('listUrl'): return
    if data.get('processing_thumbnails'): return
    db = firestore.client()
    bucket = storage.bucket()
    image_id = event.params['imageId']
    img_ref = db.collection('images').document(image_id)
    img_ref.update({'processing_thumbnails': True})
    try:
        if storage_path:
            blob = bucket.blob(storage_path)
            image_bytes = blob.download_as_bytes()
        else:
            req = urllib.request.Request(file_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req) as res: image_bytes = res.read()
        img = Image.open(BytesIO(image_bytes))
        if img.mode in ("RGBA", "P"): img = img.convert("RGB")
        orig_w, orig_h = img.size
        def resize_and_upload(target_w, suffix):
            ratio = target_w / orig_w if orig_w > target_w else 1
            resized = img.resize((target_w, int(orig_h * ratio)), Image.Resampling.LANCZOS)
            out_io = BytesIO()
            resized.save(out_io, format='WEBP', quality=80)
            out_io.seek(0)
            dest_path = f"thumbnails/{image_id}_{suffix}.webp"
            new_blob = bucket.blob(dest_path)
            new_blob.upload_from_file(out_io, content_type="image/webp")
            new_blob.metadata = {"firebaseStorageDownloadTokens": image_id}
            new_blob.patch()
            return f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{urllib.parse.quote(dest_path, safe='')}?alt=media&token={image_id}"
        grid_url = resize_and_upload(450, 'grid')
        list_url = resize_and_upload(800, 'list')
        img_ref.update({
            'gridUrl': grid_url,
            'listUrl': list_url,
            'processing_thumbnails': firestore.DELETE_FIELD,
            'width': orig_w,
            'height': orig_h
        })
        used_in = data.get('usedInFanzines', [])
        for fid in used_in:
            pages = db.collection('fanzines').document(fid).collection('pages').where(filter=firestore.FieldFilter('imageId', '==', image_id)).stream()
            for p in pages:
                p.reference.update({'gridUrl': grid_url, 'listUrl': list_url, 'width': orig_w, 'height': orig_h})
    except Exception as e:
        print(f"Thumbnail Error: {traceback.format_exc()}")
        img_ref.update({'thumbnail_error': str(e), 'processing_thumbnails': firestore.DELETE_FIELD})

def _do_pdf_ingest(fanzine_id, file_path, uploader_id):
    import fitz
    db = firestore.client()
    bucket = storage.bucket()
    fref = db.collection('fanzines').document(fanzine_id)
    try:
        blob = bucket.blob(file_path)
        if not blob.exists(): raise Exception("Source PDF missing.")
        pdf_bytes = blob.download_as_bytes()
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        n_pages = len(doc)
        for p in fref.collection('pages').stream(): p.reference.delete()
        batch = db.batch()
        batch_count = 0
        for i in range(n_pages):
            page_num = i + 1
            page = doc.load_page(i)
            pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0), alpha=False)
            img_bytes = pix.tobytes("jpeg")
            dest = f"fanzines/{fanzine_id}/pages/page_{page_num:03d}.jpg"
            img_blob = bucket.blob(dest)
            new_img_ref = db.collection('images').document()
            token = new_img_ref.id
            img_blob.metadata = {"firebaseStorageDownloadTokens": token}
            img_blob.upload_from_string(img_bytes, content_type="image/jpeg")
            img_blob.patch()
            file_url = f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/{urllib.parse.quote(dest, safe='')}?alt=media&token={token}"
            batch.set(new_img_ref, {
                'storagePath': dest,
                'fileUrl': file_url,
                'shortCode': generate_simple_shortcode(),
                'status': 'approved',
                'timestamp': firestore.SERVER_TIMESTAMP,
                'uploaderId': uploader_id,
                'folioContext': fanzine_id,
                'usedInFanzines': [fanzine_id]
            })
            batch.set(fref.collection('pages').document(), {
                'pageNumber': page_num,
                'storagePath': dest,
                'imageUrl': file_url,
                'imageId': new_img_ref.id,
                'status': 'ready',
                'uploadedAt': firestore.SERVER_TIMESTAMP
            })
            batch_count += 2
            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0
        if batch_count > 0: batch.commit()
        doc.close()
        fref.update({'processingStatus': 'images_ready', 'pageCount': n_pages})
    except Exception as e:
        print(f"Ingest Error: {traceback.format_exc()}")
        fref.update({'processingStatus': 'error', 'error_ingest': str(e)})

@storage_fn.on_object_finalized(memory=256)
def handle_pdf_upload(event: storage_fn.CloudEvent[storage_fn.StorageObjectData]):
    file_path = event.data.name
    if not file_path.endswith('.pdf') or 'uploads/raw_pdfs/' not in file_path: return
    db = firestore.client()
    short_code = ""
    is_unique = False
    while not is_unique:
        short_code = generate_simple_shortcode()
        sc_ref = db.collection('shortcodes').document(short_code.upper())
        if not sc_ref.get().exists:
            is_unique = True
            new_doc_ref = db.collection('fanzines').document()
            sc_ref.set({
                'type': 'fanzine',
                'contentId': new_doc_ref.id,
                'displayCode': short_code,
                'createdAt': firestore.SERVER_TIMESTAMP
            })
            new_doc_ref.set({
                'title': os.path.basename(file_path).replace('.pdf', '').replace('_', ' ').title(),
                'sourceFile': file_path,
                'processingStatus': 'needs_ingest',
                'isLive': False,
                'creationDate': firestore.SERVER_TIMESTAMP,
                'uploaderId': event.data.metadata.get('uploaderId') if event.data.metadata else 'unknown',
                'shortCode': short_code,
                'shortCodeKey': short_code.upper()
            })