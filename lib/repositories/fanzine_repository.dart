import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/link_parser.dart';

/// Centralized repository for all Fanzine-related database operations.
class FanzineRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Returns a stream of a specific fanzine document.
  Stream<DocumentSnapshot> watchFanzine(String fanzineId) {
    return _db.collection('fanzines').doc(fanzineId).snapshots();
  }

  /// Returns a stream of pages for a fanzine, ordered by page number.
  Stream<QuerySnapshot> watchPages(String fanzineId) {
    return _db
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber')
        .snapshots();
  }

  /// Updates top-level fanzine metadata.
  Future<void> updateFanzine(String fanzineId, Map<String, dynamic> data) async {
    await _db.collection('fanzines').doc(fanzineId).update(data);
  }

  /// Updates text for a specific page.
  Future<void> updatePageText(String fanzineId, String pageId, String text) async {
    final batch = _db.batch();
    batch.update(_db.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId), {
      'text_processed': text,
      'lastEdited': FieldValue.serverTimestamp(),
    });
    // Also sync to the master fanzine page count if needed
    await batch.commit();
  }

  /// Adds a page to a fanzine and links it to an existing image via shortcode.
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

  /// Swaps positions of two pages.
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

  /// Parses mentions across all pages and marks the fanzine as soft-published.
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

  /// Looks up a handle status in the registry.
  Future<Map<String, dynamic>?> checkHandleStatus(String handle) async {
    final doc = await _db.collection('usernames').doc(handle).get();
    return doc.exists ? doc.data() : null;
  }
}