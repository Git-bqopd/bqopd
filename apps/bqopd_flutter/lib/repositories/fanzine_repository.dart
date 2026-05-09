import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/link_parser.dart';
import '../models/fanzine.dart';
import '../models/fanzine_page.dart';

/// Centralized repository for all Fanzine-related database operations.
class FanzineRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- STREAMS ---

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

  Future<void> updatePageLayout(String fanzineId, FanzinePage page, String? spreadPosition, String sidePreference, List<FanzinePage> allPages) async {
    final batch = _db.batch();

    String finalSide = sidePreference;
    FanzinePage? linkedPage;
    String? linkedSpread;
    String? linkedSide;

    if (spreadPosition == 'start') {
      finalSide = 'left';
      linkedPage = allPages.where((p) => p.pageNumber == page.pageNumber + 1).firstOrNull;
      linkedSpread = 'end';
      linkedSide = 'right';
    } else if (spreadPosition == 'end') {
      finalSide = 'right';
      linkedPage = allPages.where((p) => p.pageNumber == page.pageNumber - 1).firstOrNull;
      linkedSpread = 'start';
      linkedSide = 'left';
    } else if (spreadPosition == null) {
      // If the user unlinks an image, automatically unlink its previously paired image
      if (page.spreadPosition == 'start') {
        linkedPage = allPages.where((p) => p.pageNumber == page.pageNumber + 1).firstOrNull;
        if (linkedPage != null && linkedPage.spreadPosition == 'end') {
          linkedSpread = null;
        } else {
          linkedPage = null; // Pair broken elsewhere, don't modify it
        }
      } else if (page.spreadPosition == 'end') {
        linkedPage = allPages.where((p) => p.pageNumber == page.pageNumber - 1).firstOrNull;
        if (linkedPage != null && linkedPage.spreadPosition == 'start') {
          linkedSpread = null;
        } else {
          linkedPage = null;
        }
      }
    }

    batch.update(page.reference, {
      'spreadPosition': spreadPosition,
      'sidePreference': finalSide,
    });

    if (linkedPage != null) {
      batch.update(linkedPage.reference, {
        'spreadPosition': linkedSpread,
        'sidePreference': linkedSide ?? linkedPage.sidePreference,
      });
    }

    await batch.commit();
  }

  Future<void> updatePageText(String fanzineId, String pageId, String text) async {
    final batch = _db.batch();
    batch.update(_db.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId), {
      'text_processed': text,
      'lastEdited': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> addExistingImageToFolio(
      String fanzineId,
      String imageId,
      String imageUrl, {
        int? width,
        int? height,
      }) async {
    final fzRef = _db.collection('fanzines').doc(fanzineId);
    final pagesCol = fzRef.collection('pages');

    await _db.runTransaction((transaction) async {
      final pagesQuery = await pagesCol.get();

      int nextNum = 1;
      if (pagesQuery.docs.isNotEmpty) {
        final maxNum = pagesQuery.docs
            .map((d) => (d.data()['pageNumber'] as int? ?? 0))
            .fold(0, (prev, element) => element > prev ? element : prev);
        nextNum = maxNum + 1;
      }

      final newPageRef = pagesCol.doc();
      transaction.set(newPageRef, {
        'imageId': imageId,
        'imageUrl': imageUrl,
        'pageNumber': nextNum,
        'status': 'ready',
        'width': width,
        'height': height,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(_db.collection('images').doc(imageId), {
        'usedInFanzines': FieldValue.arrayUnion([fanzineId])
      });
    });
  }

  Future<void> removePageFromFolio(String fanzineId, FanzinePage page, List<FanzinePage> allPages) async {
    final pagesCol = _db.collection('fanzines').doc(fanzineId).collection('pages');

    await _db.runTransaction((transaction) async {
      final snapshot = await pagesCol.get();
      transaction.delete(page.reference);
      final remainingDocs = snapshot.docs.where((d) => d.id != page.id).toList();
      remainingDocs.sort((a, b) => (a.data()['pageNumber'] as int).compareTo(b.data()['pageNumber'] as int));

      int currentNum = 1;
      for (int i = 0; i < remainingDocs.length; i++) {
        if ((remainingDocs[i].data()['pageNumber'] as int) > 0) {
          transaction.update(remainingDocs[i].reference, {'pageNumber': currentNum++});
        }
      }
    });
  }

  Future<void> togglePageOrdering(String fanzineId, FanzinePage page, bool shouldOrder) async {
    final pagesCol = _db.collection('fanzines').doc(fanzineId).collection('pages');

    await _db.runTransaction((transaction) async {
      final snapshot = await pagesCol.get();
      final docs = snapshot.docs;

      if (shouldOrder) {
        int maxNum = docs.map((d) => d.data()['pageNumber'] as int? ?? 0)
            .fold(0, (prev, element) => element > prev ? element : prev);
        transaction.update(page.reference, {'pageNumber': maxNum + 1});
      } else {
        transaction.update(page.reference, {'pageNumber': 0});
        final others = docs.where((d) => d.id != page.id).toList();
        others.sort((a, b) => (a.data()['pageNumber'] as int).compareTo(b.data()['pageNumber'] as int));

        int currentNum = 1;
        for (final doc in others) {
          if ((doc.data()['pageNumber'] as int) > 0) {
            transaction.update(doc.reference, {'pageNumber': currentNum++});
          }
        }
      }
    });
  }

  Future<void> deleteAssetCompletely(String fanzineId, String imageId, bool isDirectUpload) async {
    final db = FirebaseFirestore.instance;
    final pagesQuery = await db.collection('fanzines').doc(fanzineId).collection('pages').where('imageId', isEqualTo: imageId).get();
    final batch = db.batch();
    for (var doc in pagesQuery.docs) {
      batch.delete(doc.reference);
    }

    if (isDirectUpload) {
      final imgDoc = await db.collection('images').doc(imageId).get();
      if (imgDoc.exists) {
        final path = imgDoc.data()?['storagePath'];
        if (path != null) await FirebaseStorage.instance.ref(path).delete().catchError((_) => null);
        batch.delete(db.collection('images').doc(imageId));
      }
    } else {
      batch.update(db.collection('images').doc(imageId), {
        'usedInFanzines': FieldValue.arrayRemove([fanzineId])
      });
    }
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
    final data = imageDoc.data();

    await addExistingImageToFolio(
      fanzineId,
      imageDoc.id,
      data['fileUrl'],
      width: data['width'],
      height: data['height'],
    );
  }

  Future<void> reorderPageModel(String fanzineId, FanzinePage page, int delta, List<FanzinePage> allPages) async {
    final pagesCol = _db.collection('fanzines').doc(fanzineId).collection('pages');

    await _db.runTransaction((transaction) async {
      final snapshot = await pagesCol.get();
      final docs = snapshot.docs.where((d) => (d.data()['pageNumber'] as int) > 0).toList();

      List<Map<String, dynamic>> items = docs.map((d) => {
        'ref': d.reference,
        'id': d.id,
        'pageNumber': d.data()['pageNumber'] as int? ?? 0,
      }).toList();

      items.sort((a, b) => a['pageNumber'].compareTo(b['pageNumber']));

      int oldIndex = items.indexWhere((item) => item['id'] == page.id);
      if (oldIndex == -1) return;

      int newIndex = oldIndex + delta;
      if (newIndex < 0 || newIndex >= items.length) return;

      final movedItem = items.removeAt(oldIndex);
      items.insert(newIndex, movedItem);

      for (int i = 0; i < items.length; i++) {
        transaction.update(items[i]['ref'] as DocumentReference, {'pageNumber': i + 1});
      }
    });
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