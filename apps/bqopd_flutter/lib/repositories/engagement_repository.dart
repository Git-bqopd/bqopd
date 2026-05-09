import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository for social interactions: Likes, Comments, and Following.
class EngagementRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _commentsCollection =>
      _db.collection('artifacts').doc('bqopd').collection('public').doc('data').collection('comments');

  // --- UGC Level Interactions (Likes) ---

  Future<void> toggleImageLike({
    required String imageId,
    required String? fanzineId,
    required bool isCurrentlyLiked,
  }) async {
    final user = _auth.currentUser;
    if (user == null || imageId.isEmpty) return;

    final imageRef = _db.collection('images').doc(imageId);
    final activityRef = _db
        .collection('Users')
        .doc(user.uid)
        .collection('activity')
        .doc('likes')
        .collection('images')
        .doc(imageId);

    final batch = _db.batch();
    if (isCurrentlyLiked) {
      batch.update(imageRef, {'likeCount': FieldValue.increment(-1)});
      batch.delete(activityRef);
    } else {
      batch.update(imageRef, {'likeCount': FieldValue.increment(1)});
      batch.set(activityRef, {
        'imageId': imageId,
        'fanzineContext': fanzineId,
        'likedAt': FieldValue.serverTimestamp()
      });
    }
    await batch.commit();
  }

  Stream<bool> isImageLiked(String imageId) {
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

  // --- Comment Management ---

  Stream<QuerySnapshot> watchImageComments(String imageId) {
    return _commentsCollection.where('contentId', isEqualTo: imageId).snapshots();
  }

  Future<void> addComment({
    required String imageId,
    required String text,
    String? fanzineId,
    String? fanzineTitle,
    String? displayName,
    String? username,
  }) async {
    final user = _auth.currentUser;
    if (user == null || text.trim().isEmpty) return;

    final batch = _db.batch();
    final commentDoc = _commentsCollection.doc();

    batch.set(commentDoc, {
      'contentId': imageId,
      'userId': user.uid,
      'displayName': displayName ?? '',
      'username': username ?? 'user',
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'context': {
        'fanzineId': fanzineId,
        'fanzineTitle': fanzineTitle,
      },
    });

    if (imageId.isNotEmpty) {
      batch.update(_db.collection('images').doc(imageId), {
        'commentCount': FieldValue.increment(1),
      });
    }
    await batch.commit();
  }

  Future<void> deleteComment(String commentId, String imageId) async {
    final batch = _db.batch();
    batch.delete(_commentsCollection.doc(commentId));
    if (imageId.isNotEmpty) {
      batch.update(_db.collection('images').doc(imageId), {
        'commentCount': FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }

  Future<void> toggleCommentLike(String commentId, bool isCurrentlyLiked) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final batch = _db.batch();
    final commentRef = _commentsCollection.doc(commentId);
    final activityRef = _db.collection('Users').doc(user.uid).collection('activity').doc('likes').collection('comments').doc(commentId);

    if (isCurrentlyLiked) {
      batch.update(commentRef, {'likeCount': FieldValue.increment(-1)});
      batch.delete(activityRef);
    } else {
      batch.update(commentRef, {'likeCount': FieldValue.increment(1)});
      batch.set(activityRef, {'likedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  Stream<bool> isCommentLiked(String commentId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);
    return _db.collection('Users').doc(user.uid).collection('activity').doc('likes').collection('comments').doc(commentId).snapshots().map((doc) => doc.exists);
  }

  // --- Follow Logic (Unified Profiles) ---

  Stream<bool> isFollowing(String targetUid) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);
    return _db.collection('profiles').doc(user.uid).collection('following').doc(targetUid).snapshots().map((doc) => doc.exists);
  }

  Future<void> setFollowStatus(String targetUid, bool follow) async {
    final user = _auth.currentUser;
    if (user == null || user.uid == targetUid) return;

    final followingRef = _db.collection('profiles').doc(user.uid).collection('following').doc(targetUid);

    // IDEMPOTENCY CHECK
    final doc = await followingRef.get();
    if (follow && doc.exists) return;
    if (!follow && !doc.exists) return;

    final batch = _db.batch();

    final followersRef = _db.collection('profiles').doc(targetUid).collection('followers').doc(user.uid);
    final myProfileRef = _db.collection('profiles').doc(user.uid);
    final targetProfileRef = _db.collection('profiles').doc(targetUid);

    if (follow) {
      batch.set(followingRef, {'followedAt': FieldValue.serverTimestamp()});
      batch.set(followersRef, {'followerAt': FieldValue.serverTimestamp()});
      batch.set(myProfileRef, {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
      batch.set(targetProfileRef, {'followerCount': FieldValue.increment(1)}, SetOptions(merge: true));
    } else {
      batch.delete(followingRef);
      batch.delete(followersRef);
      batch.set(myProfileRef, {'followingCount': FieldValue.increment(-1)}, SetOptions(merge: true));
      batch.set(targetProfileRef, {'followerCount': FieldValue.increment(-1)}, SetOptions(merge: true));
    }
    await batch.commit();
  }
}