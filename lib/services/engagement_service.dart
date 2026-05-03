import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Handles persistence for Likes, Comments, Follows, and Hashtags.
class EngagementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _commentsCollection =>
      _db.collection('artifacts').doc('bqopd').collection('public').doc('data').collection('comments');

  // --- UGC Likes (Canonical) ---

  Future<void> toggleLike({
    required String imageId,
    required String? fanzineId,
    required bool isCurrentlyLiked,
  }) async {
    final user = _auth.currentUser;
    if (user == null || imageId.isEmpty) return;

    final userActivityRef = _db
        .collection('Users')
        .doc(user.uid)
        .collection('activity')
        .doc('likes')
        .collection('images')
        .doc(imageId);

    final imageRef = _db.collection('images').doc(imageId);
    final batch = _db.batch();

    if (isCurrentlyLiked) {
      batch.update(imageRef, {'likeCount': FieldValue.increment(-1)});
      batch.delete(userActivityRef);
    } else {
      batch.update(imageRef, {'likeCount': FieldValue.increment(1)});
      batch.set(userActivityRef, {
        'imageId': imageId,
        'fanzineIdContext': fanzineId,
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

  Stream<bool> isLikedStream(String imageId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);

    return _db
        .collection('Users')
        .doc(user.uid)
        .collection('activity')
        .doc('likes')
        .collection('images')
        .doc(imageId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  // --- Follow Logic (Unified Profiles) ---

  Future<void> followUser(String targetUid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid == targetUid) return;

    final followingRef = _db.collection('profiles').doc(currentUser.uid).collection('following').doc(targetUid);

    // IDEMPOTENCY CHECK: Only proceed if not already following
    final doc = await followingRef.get();
    if (doc.exists) return;

    final batch = _db.batch();

    batch.set(followingRef, {'followedAt': FieldValue.serverTimestamp()});

    final followersRef = _db.collection('profiles').doc(targetUid).collection('followers').doc(currentUser.uid);
    batch.set(followersRef, {'followerAt': FieldValue.serverTimestamp()});

    batch.set(_db.collection('profiles').doc(currentUser.uid), {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
    batch.set(_db.collection('profiles').doc(targetUid), {'followerCount': FieldValue.increment(1)}, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> unfollowUser(String targetUid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final followingRef = _db.collection('profiles').doc(currentUser.uid).collection('following').doc(targetUid);

    // IDEMPOTENCY CHECK: Only proceed if actually following
    final doc = await followingRef.get();
    if (!doc.exists) return;

    final batch = _db.batch();

    batch.delete(followingRef);
    batch.delete(_db.collection('profiles').doc(targetUid).collection('followers').doc(currentUser.uid));

    batch.set(_db.collection('profiles').doc(currentUser.uid), {'followingCount': FieldValue.increment(-1)}, SetOptions(merge: true));
    batch.set(_db.collection('profiles').doc(targetUid), {'followerCount': FieldValue.increment(-1)}, SetOptions(merge: true));

    await batch.commit();
  }

  Stream<bool> isFollowingStream(String targetUid) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);
    return _db.collection('profiles').doc(user.uid).collection('following').doc(targetUid).snapshots().map((doc) => doc.exists);
  }

  // --- Hashtag / Voting Logic ---

  Future<void> toggleHashtag(String imageId, String tag, bool isVoting) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final imageRef = _db.collection('images').doc(imageId);
    final cleanTag = tag.toLowerCase().replaceAll('#', '').trim();
    if (cleanTag.isEmpty) return;

    if (isVoting) {
      final Map<String, dynamic> updateData = {};
      updateData['tags.$cleanTag'] = FieldValue.arrayUnion([user.uid]);
      if (cleanTag == 'approved') {
        updateData['status'] = 'approved';
      }
      await imageRef.update(updateData);
    } else {
      // Unvoting Logic using a Transaction to ensure safe deletion of empty tags
      try {
        await _db.runTransaction((transaction) async {
          final snapshot = await transaction.get(imageRef);
          if (!snapshot.exists) return;

          final data = snapshot.data()!;
          final tagsMap = data['tags'] as Map<String, dynamic>? ?? {};
          final voters = tagsMap[cleanTag] as List<dynamic>? ?? [];

          final Map<String, dynamic> updateData = {};

          if (voters.length <= 1 && voters.contains(user.uid)) {
            // User is the last/only voter. Safe to delete the tag key completely.
            updateData['tags.$cleanTag'] = FieldValue.delete();
          } else {
            // There are other voters. Just pull the user's ID out.
            updateData['tags.$cleanTag'] = FieldValue.arrayRemove([user.uid]);
          }

          if (cleanTag == 'approved') {
            updateData['status'] = 'pending';
          }

          transaction.update(imageRef, updateData);
        });
      } catch (e) {
        debugPrint("Error removing hashtag: $e");
      }
    }
  }
}