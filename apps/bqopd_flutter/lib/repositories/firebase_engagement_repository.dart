import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bqopd_core/bqopd_core.dart';

class FirebaseEngagementRepository implements IEngagementRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _commentsCol => _db.collection('artifacts').doc('bqopd').collection('public').doc('data').collection('comments');

  @override
  Future<void> toggleImageLike({required String imageId, required String? fanzineId, required bool isCurrentlyLiked}) async {
    final user = _auth.currentUser;
    if (user == null || imageId.isEmpty) return;
    final batch = _db.batch();
    final imgRef = _db.collection('images').doc(imageId);
    final actRef = _db.collection('Users').doc(user.uid).collection('activity').doc('likes').collection('images').doc(imageId);

    if (isCurrentlyLiked) {
      batch.update(imgRef, {'likeCount': FieldValue.increment(-1)});
      batch.delete(actRef);
    } else {
      batch.update(imgRef, {'likeCount': FieldValue.increment(1)});
      batch.set(actRef, {'imageId': imageId, 'fanzineContext': fanzineId, 'likedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  @override
  Stream<bool> isImageLiked(String imageId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);
    return _db.collection('Users').doc(user.uid).collection('activity').doc('likes').collection('images').doc(imageId).snapshots().map((d) => d.exists);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchImageComments(String imageId) {
    return _commentsCol.where('contentId', isEqualTo: imageId).snapshots().map((s) => s.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      data['_id'] = d.id;
      return data;
    }).toList());
  }

  @override
  Future<void> addComment({required String imageId, required String text, String? fanzineId, String? fanzineTitle, String? displayName, String? username}) async {
    final user = _auth.currentUser;
    if (user == null || text.trim().isEmpty) return;
    final batch = _db.batch();
    final doc = _commentsCol.doc();
    batch.set(doc, {
      'contentId': imageId, 'userId': user.uid, 'text': text.trim(), 'createdAt': FieldValue.serverTimestamp(),
      'displayName': displayName, 'username': username, 'likeCount': 0,
      'context': {'fanzineId': fanzineId, 'fanzineTitle': fanzineTitle}
    });
    if (imageId.isNotEmpty) batch.update(_db.collection('images').doc(imageId), {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  @override
  Future<void> deleteComment(String commentId, String imageId) async {
    final batch = _db.batch();
    batch.delete(_commentsCol.doc(commentId));
    if (imageId.isNotEmpty) batch.update(_db.collection('images').doc(imageId), {'commentCount': FieldValue.increment(-1)});
    await batch.commit();
  }

  @override
  Future<void> toggleCommentLike(String commentId, bool isCurrentlyLiked) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final batch = _db.batch();
    final commentRef = _commentsCol.doc(commentId);
    final actRef = _db.collection('Users').doc(user.uid).collection('activity').doc('likes').collection('comments').doc(commentId);
    if (isCurrentlyLiked) {
      batch.update(commentRef, {'likeCount': FieldValue.increment(-1)});
      batch.delete(actRef);
    } else {
      batch.update(commentRef, {'likeCount': FieldValue.increment(1)});
      batch.set(actRef, {'likedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  @override
  Stream<bool> isCommentLiked(String commentId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);
    return _db.collection('Users').doc(user.uid).collection('activity').doc('likes').collection('comments').doc(commentId).snapshots().map((d) => d.exists);
  }

  @override
  Stream<bool> isFollowing(String targetUid) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);
    return _db.collection('profiles').doc(user.uid).collection('following').doc(targetUid).snapshots().map((d) => d.exists);
  }

  @override
  Future<void> setFollowStatus(String targetUid, bool follow) async {
    final user = _auth.currentUser;
    if (user == null || user.uid == targetUid) return;
    final followingRef = _db.collection('profiles').doc(user.uid).collection('following').doc(targetUid);
    final followersRef = _db.collection('profiles').doc(targetUid).collection('followers').doc(user.uid);
    final batch = _db.batch();
    if (follow) {
      batch.set(followingRef, {'followedAt': FieldValue.serverTimestamp()});
      batch.set(followersRef, {'followerAt': FieldValue.serverTimestamp()});
      batch.set(_db.collection('profiles').doc(user.uid), {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
      batch.set(_db.collection('profiles').doc(targetUid), {'followerCount': FieldValue.increment(1)}, SetOptions(merge: true));
    } else {
      batch.delete(followingRef); batch.delete(followersRef);
      batch.set(_db.collection('profiles').doc(user.uid), {'followingCount': FieldValue.increment(-1)}, SetOptions(merge: true));
      batch.set(_db.collection('profiles').doc(targetUid), {'followerCount': FieldValue.increment(-1)}, SetOptions(merge: true));
    }
    await batch.commit();
  }
}