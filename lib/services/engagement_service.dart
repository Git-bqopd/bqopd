import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles persistence for Likes and Comments as defined in the bqopd Design Document.
class EngagementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference _pageRef(String fanzineId, String pageId) {
    return _db.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId);
  }

  /// Toggles a like for a specific page.
  /// Increments/Decrements page likeCount and mirrors state to the user document.
  Future<void> toggleLike({
    required String fanzineId,
    required String pageId,
    required bool isCurrentlyLiked,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final pageRef = _pageRef(fanzineId, pageId);
    final userActivityRef = _db
        .collection('Users')
        .doc(user.uid)
        .collection('activity')
        .doc('likes')
        .collection('pages')
        .doc(pageId);

    final batch = _db.batch();

    if (isCurrentlyLiked) {
      batch.update(pageRef, {'likeCount': FieldValue.increment(-1)});
      batch.delete(userActivityRef);
    } else {
      batch.update(pageRef, {'likeCount': FieldValue.increment(1)});
      batch.set(userActivityRef, {
        'fanzineId': fanzineId,
        'likedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Adds a comment and updates the parent count.
  Future<void> addComment({
    required String fanzineId,
    required String pageId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null || text.trim().isEmpty) return;

    final pageRef = _pageRef(fanzineId, pageId);
    final commentRef = pageRef.collection('comments').doc();

    await _db.runTransaction((transaction) async {
      transaction.set(commentRef, {
        'uid': user.uid,
        'username': user.displayName ?? user.email?.split('@').first ?? 'Anonymous',
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(pageRef, {'commentCount': FieldValue.increment(1)});
    });
  }

  /// Returns a stream of comments for a specific page.
  Stream<QuerySnapshot> getCommentsStream(String fanzineId, String pageId) {
    return _pageRef(fanzineId, pageId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Checks if a user has liked a specific page.
  Stream<bool> isLikedStream(String pageId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);

    return _db
        .collection('Users')
        .doc(user.uid)
        .collection('activity')
        .doc('likes')
        .collection('pages')
        .doc(pageId)
        .snapshots()
        .map((doc) => doc.exists);
  }
}