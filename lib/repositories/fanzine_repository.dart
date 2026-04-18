import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/link_parser.dart';
import '../models/fanzine.dart';
import '../models/fanzine_page.dart';

/// Centralized repository for all Fanzine-related database operations.
class FanzineRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- LEGACY STREAMS (Kept intact to avoid breaking CuratorWorkbenchBloc) ---

  Stream<DocumentSnapshot> watchFanzine(String fanzineId) {
    return _db.collection('fanzines').doc(fanzineId).snapshots();
  }

  Stream<QuerySnapshot> watchPages(String fanzineId) {
    return _db
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber')
        .snapshots();
  }

  // --- STRICT MODEL STREAMS ---

  Stream<Fanzine> watchFanzineModel(String fanzineId) {
    return _db.collection('fanzines').doc(fanzineId).snapshots().map((doc) => Fanzine.fromFirestore(doc));
  }

  Stream<List<FanzinePage>> watchPageModels(String fanzineId) {
    return _db
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber')
        .snapshots()
        .map((snap) => snap.docs.map((d) => FanzinePage.fromFirestore(d)).toList());
  }

  // --- OPERATIONS ---

  Future<void> updateFanzine(String fanzineId, Map<String, dynamic> data) async {
    await _db.collection('fanzines').doc(fanzineId).update(data);
  }

  Future<void> updatePageText(String fanzineId, String pageId, String text) async {
    final batch = _db.batch();
    batch.update(_db.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId), {
      'text_processed': text,
      'lastEdited': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> addPageByShortcode(String fanzineId, String shortcode) async {
    final imageQuery = await _db
        .collection('images')
        .where('shortCode', isEqualTo: shortcode)
        .limit(1)
        .get();

    if (imageQuery.docs.isEmpty) {
      throw Exception('Image shortcode not found.');
    }

    final imageDoc = imageQuery.docs.first;
    final imageId = imageDoc.id;
    final imageUrl = imageDoc.data()['fileUrl'];

    final pagesQuery = await _db
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber', descending: true)
        .limit(1)
        .get();

    int nextNum = pagesQuery.docs.isNotEmpty
        ? (pagesQuery.docs.first.data()['pageNumber'] ?? 0) + 1
        : 1;

    final batch = _db.batch();
    final newPageRef = _db.collection('fanzines').doc(fanzineId).collection('pages').doc();

    batch.set(newPageRef, {
      'imageId': imageId,
      'imageUrl': imageUrl,
      'pageNumber': nextNum,
      'status': 'ready'
    });

    batch.update(_db.collection('images').doc(imageId), {
      'usedInFanzines': FieldValue.arrayUnion([fanzineId])
    });

    await batch.commit();
  }

  /// Swaps positions of two pages using the legacy Snapshot method.
  Future<void> reorderPage(String fanzineId, DocumentSnapshot doc, int delta, List<DocumentSnapshot> allPages) async {
    final int currentPos = doc.get('pageNumber');
    final int targetPos = currentPos + delta;

    if (targetPos < 1 || targetPos > allPages.length) return;

    final targetDoc = allPages.firstWhere((p) => p.get('pageNumber') == targetPos);

    final batch = _db.batch();
    batch.update(doc.reference, {'pageNumber': targetPos});
    batch.update(targetDoc.reference, {'pageNumber': currentPos});
    await batch.commit();
  }

  /// Swaps positions of two pages using strictly typed models.
  Future<void> reorderPageModel(String fanzineId, FanzinePage page, int delta, List<FanzinePage> allPages) async {
    final int currentPos = page.pageNumber;
    final int targetPos = currentPos + delta;

    if (targetPos < 1 || targetPos > allPages.length) return;

    final targetPage = allPages.firstWhere((p) => p.pageNumber == targetPos);

    final batch = _db.batch();
    batch.update(page.reference, {'pageNumber': targetPos});
    batch.update(targetPage.reference, {'pageNumber': currentPos});
    await batch.commit();
  }

  Future<void> softPublish(String fanzineId) async {
    final allMentions = <String>{};
    final pagesSnap = await _db.collection('fanzines').doc(fanzineId).collection('pages').get();

    for (final doc in pagesSnap.docs) {
      final data = doc.data();
      final text = data['text_processed'] ?? '';
      final mentions = await LinkParser.parseMentions(text);
      allMentions.addAll(mentions);
    }

    await _db.collection('fanzines').doc(fanzineId).update({
      'status': 'working',
      'mentionedUsers': allMentions.toList(),
      'publishedAt': FieldValue.serverTimestamp(),
      'isSoftPublished': true,
      'pageCount': pagesSnap.docs.length,
    });
  }

  Future<Map<String, dynamic>?> checkHandleStatus(String handle) async {
    final doc = await _db.collection('usernames').doc(handle).get();
    return doc.exists ? doc.data() : null;
  }
}