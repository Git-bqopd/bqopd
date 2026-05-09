import firebase_admin
from firebase_admin import firestore

if not firebase_admin._apps:
    firebase_admin.initialize_app()

db = firestore.client()
fid = "ZRK4fYci8LFX0qP3Q0hh"
fref = db.collection('fanzines').document(fid)
data = fref.get().to_dict()

print(f"Fanzine: {data.get('title')} ({fid})")
print(f"Status: {data.get('processingStatus')}")

pages_ref = fref.collection('pages').order_by('pageNumber').stream()
for p in pages_ref:
    pdata = p.to_dict()
    print(f"Page {pdata.get('pageNumber')}: {pdata.get('status')} - Error: {pdata.get('errorLog')}")
