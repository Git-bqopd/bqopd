import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Concrete Firebase implementation of the IFanzineRepository interface.
class FirebaseFanzineRepository implements IFanzineRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Stream<Fanzine> watchFanzineModel(String fanzineId) {
    return _db.collection('fanzines').doc(fanzineId).snapshots().map((doc) => Fanzine.fromMap(doc.id, doc.data() as Map<String, dynamic>));
  }

  @override
  Stream<List<FanzinePage>> watchPageModels(String fanzineId) {
    return _db
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber')
        .snapshots()
        .map((snap) => snap.docs.map((d) => FanzinePage.fromMap(d.id, d.data())).toList());
  }

  @override
  Future<void> updateFanzine(String fanzineId, Map<String, dynamic> data) async {
    await _db.collection('fanzines').doc(fanzineId).update(data);
  }

  @override
  Future<void> updatePageLayout(String fanzineId, FanzinePage page, String? spreadPosition, String sidePreference, List<FanzinePage> allPages) async {
    final batch = _db.batch();
    final pageRef = _db.collection('fanzines').doc(fanzineId).collection('pages').doc(page.id);
    batch.update(pageRef, {
      'spreadPosition': spreadPosition,
      'sidePreference': sidePreference,
    });
    await batch.commit();
  }

  @override
  Future<void> addPageByShortcode(String fanzineId, String shortcode) async {
    final imageQuery = await _db.collection('images').where('shortCode', isEqualTo: shortcode).limit(1).get();
    if (imageQuery.docs.isEmpty) throw Exception('Image shortcode not found.');
    final imageDoc = imageQuery.docs.first;
    final data = imageDoc.data();
    await addExistingImageToFolio(fanzineId, imageDoc.id, data['fileUrl'], width: data['width'], height: data['height']);
  }

  @override
  Future<void> addExistingImageToFolio(String fanzineId, String imageId, String imageUrl, {int? width, int? height}) async {
    final pagesCol = _db.collection('fanzines').doc(fanzineId).collection('pages');
    await _db.runTransaction((transaction) async {
      final pagesQuery = await pagesCol.get();
      int nextNum = pagesQuery.docs.length + 1;
      transaction.set(pagesCol.doc(), {
        'imageId': imageId, 'imageUrl': imageUrl, 'pageNumber': nextNum, 'status': 'ready',
        'width': width, 'height': height, 'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(_db.collection('images').doc(imageId), {'usedInFanzines': FieldValue.arrayUnion([fanzineId])});
    });
  }

  @override
  Future<void> removePageFromFolio(String fanzineId, FanzinePage page, List<FanzinePage> allPages) async {
    await _db.collection('fanzines').doc(fanzineId).collection('pages').doc(page.id).delete();
  }

  @override
  Future<void> togglePageOrdering(String fanzineId, FanzinePage page, bool shouldOrder) async {
    await _db.collection('fanzines').doc(fanzineId).collection('pages').doc(page.id).update({'pageNumber': shouldOrder ? 1 : 0});
  }

  @override
  Future<void> reorderPageModel(String fanzineId, FanzinePage page, int delta, List<FanzinePage> allPages) async {
    await _db.collection('fanzines').doc(fanzineId).collection('pages').doc(page.id).update({'pageNumber': page.pageNumber + delta});
  }

  @override
  Future<void> deleteAssetCompletely(String fanzineId, String imageId, bool isDirectUpload) async {
    if (isDirectUpload) {
      await _db.collection('images').doc(imageId).delete();
    }
  }

  @override
  Future<void> softPublish(String fanzineId) async {
    await _db.collection('fanzines').doc(fanzineId).update({'isSoftPublished': true});
  }

  @override
  Future<String> insertPublisherPage(String fanzineId, int afterPageNumber, String initialText, List<FanzinePage> allPages) async {
    final pageId = 'page_${DateTime.now().millisecondsSinceEpoch}';
    final imageId = 'temp_pub_page_${DateTime.now().millisecondsSinceEpoch}';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'system';

    final batch = _db.batch();
    final imgRef = _db.collection('images').doc(imageId);

    batch.set(imgRef, {
      'uid': uid,
      'uploaderId': uid,
      'type': 'template',
      'templateId': 'basic_text',
      'text': initialText,
      'text_corrected': initialText,
      'text_linked': initialText,
      'title': 'Generated Page',
      'isGenerated': true,
      'width': 2000,
      'height': 3200,
      'aspectRatio': 0.625,
      'is5x8': true,
      'shortCode': ShortcodeGenerator.generateStandardCode(),
      'folioContext': fanzineId,
      'usedInFanzines': [fanzineId],
      'timestamp': FieldValue.serverTimestamp(),
    });

    for (final p in allPages) {
      if (p.pageNumber > afterPageNumber) {
        batch.update(_db.collection('fanzines').doc(fanzineId).collection('pages').doc(p.id), {
          'pageNumber': p.pageNumber + 1
        });
      }
    }

    batch.set(_db.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId), {
      'imageId': imageId,
      'pageNumber': afterPageNumber + 1,
      'status': 'ready',
      'templateId': 'basic_text',
      'width': 2000,
      'height': 3200,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return imageId;
  }
}