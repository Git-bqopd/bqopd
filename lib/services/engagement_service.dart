import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles persistence for Likes, Comments, and Follows.
class EngagementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference _pageRef(String fanzineId, String pageId) {
    return _db.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId);
  }

  // --- Likes & Comments ---

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

  Stream<QuerySnapshot> getCommentsStream(String fanzineId, String pageId) {
    return _pageRef(fanzineId, pageId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots();
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

  /// Establishes a follow relationship.
  Future<void> followUser(String targetUid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid == targetUid) return;

    final batch = _db.batch();

    // 1. Add to following subcollection of current user
    final followingRef = _db.collection('Users').doc(currentUser.uid).collection('following').doc(targetUid);
    batch.set(followingRef, {'followedAt': FieldValue.serverTimestamp()});

    // 2. Add to followers subcollection of target user
    final followersRef = _db.collection('Users').doc(targetUid).collection('followers').doc(currentUser.uid);
    batch.set(followersRef, {'followerAt': FieldValue.serverTimestamp()});

    // 3. Increment counts on both main documents
    batch.set(_db.collection('Users').doc(currentUser.uid), {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
    batch.set(_db.collection('Users').doc(targetUid), {'followerCount': FieldValue.increment(1)}, SetOptions(merge: true));

    await batch.commit();
  }

  /// Removes a follow relationship.
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

  /// Checks if current user is following the target.
  Stream<bool> isFollowingStream(String targetUid) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);

    return _db
        .collection('Users')
        .doc(user.uid)
        .collection('following')
        .doc(targetUid)
        .snapshots()
        .map((doc) => doc.exists);
  }
}