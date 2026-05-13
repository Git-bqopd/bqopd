import 'package:cloud_firestore/cloud_firestore.dart';
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
}