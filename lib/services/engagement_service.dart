import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles persistence for Likes, Comments, and Follows.
class EngagementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Rule 1 Compliant Path for Public Data
  CollectionReference get _commentsCollection =>
      _db.collection('artifacts').doc('bqopd').collection('public').doc('data').collection('comments');

  DocumentReference _pageRef(String fanzineId, String pageId) {
    return _db.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId);
  }

  // --- Page Likes ---

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

  // --- Comments ---

  Future<void> addComment({
    required String imageId,
    required String? fanzineId,
    required String? fanzineTitle,
    required String text,
    required String? displayName,
    required String? username,
    String? parentId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || text.trim().isEmpty) return;

    final commentDoc = _commentsCollection.doc();

    await commentDoc.set({
      'contentId': imageId,
      'userId': user.uid,
      'displayName': displayName ?? '',
      'username': username ?? 'user',
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'parentId': parentId,
      'context': {
        'fanzineId': fanzineId,
        'fanzineTitle': fanzineTitle,
      },
    });

    if (imageId.isNotEmpty) {
      await _db.collection('images').doc(imageId).update({
        'commentCount': FieldValue.increment(1),
      }).catchError((_) => null);
    }
  }

  /// Removes a comment and decrements the counter on the image.
  Future<void> deleteComment(String commentId, String imageId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _commentsCollection.doc(commentId).delete();

    if (imageId.isNotEmpty) {
      await _db.collection('images').doc(imageId).update({
        'commentCount': FieldValue.increment(-1),
      }).catchError((_) => null);
    }
  }

  Stream<QuerySnapshot> getCommentsStream(String imageId) {
    return _commentsCollection
        .where('contentId', isEqualTo: imageId)
        .snapshots();
  }

  Future<void> toggleCommentLike(String commentId, bool isCurrentlyLiked) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final commentRef = _commentsCollection.doc(commentId);
    final userActivityRef = _db
        .collection('Users')
        .doc(user.uid)
        .collection('activity')
        .doc('likes')
        .collection('comments')
        .doc(commentId);

    final batch = _db.batch();

    if (isCurrentlyLiked) {
      batch.update(commentRef, {'likeCount': FieldValue.increment(-1)});
      batch.delete(userActivityRef);
    } else {
      batch.update(commentRef, {'likeCount': FieldValue.increment(1)});
      batch.set(userActivityRef, {
        'likedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Stream<bool> isCommentLikedStream(String commentId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);

    return _db
        .collection('Users')
        .doc(user.uid)
        .collection('activity')
        .doc('likes')
        .collection('comments')
        .doc(commentId)
        .snapshots()
        .map((doc) => doc.exists);
  }

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

  // --- Follow Logic ---

  Future<void> followUser(String targetUid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid == targetUid) return;

    final batch = _db.batch();
    final followingRef = _db.collection('Users').doc(currentUser.uid).collection('following').doc(targetUid);
    batch.set(followingRef, {'followedAt': FieldValue.serverTimestamp()});
    final followersRef = _db.collection('Users').doc(targetUid).collection('followers').doc(currentUser.uid);
    batch.set(followersRef, {'followerAt': FieldValue.serverTimestamp()});
    batch.set(_db.collection('Users').doc(currentUser.uid), {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
    batch.set(_db.collection('Users').doc(targetUid), {'followerCount': FieldValue.increment(1)}, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> unfollowUser(String targetUid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final batch = _db.batch();
    batch.delete(_db.collection('Users').doc(currentUser.uid).collection('following').doc(targetUid));
    batch.delete(_db.collection('Users').doc(targetUid).collection('followers').doc(currentUser.uid));
    batch.set(_db.collection('Users').doc(currentUser.uid), {'followingCount': FieldValue.increment(-1)}, SetOptions(merge: true));
    batch.set(_db.collection('Users').doc(targetUid), {'followerCount': FieldValue.increment(-1)}, SetOptions(merge: true));
    await batch.commit();
  }

  Stream<bool> isFollowingStream(String targetUid) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);
    return _db.collection('Users').doc(user.uid).collection('following').doc(targetUid).snapshots().map((doc) => doc.exists);
  }
}