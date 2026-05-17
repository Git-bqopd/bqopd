import 'dart:async';
import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

class WebEngagementRepository implements IEngagementRepository {
  @override
  Future<void> toggleImageLike({required String imageId, required String? fanzineId, required bool isCurrentlyLiked}) async {
    final uid = getCurrentUserId();
    if (uid == null || imageId.isEmpty) return;

    if (isCurrentlyLiked) {
      await fsUpdateDoc('images/$imageId', jsonEncode(WebFieldValue.increment(-1)));
      await fsDeleteDoc('Users/$uid/activity/likes/images/$imageId');
    } else {
      await fsUpdateDoc('images/$imageId', jsonEncode(WebFieldValue.increment(1)));
      await fsSetDoc('Users/$uid/activity/likes/images/$imageId', jsonEncode({
        'imageId': imageId, 'fanzineContext': fanzineId, 'likedAt': WebFieldValue.serverTimestamp()
      }), true);
    }
  }

  @override
  Stream<bool> isImageLiked(String imageId) {
    final uid = getCurrentUserId();
    if (uid == null) return Stream.value(false);
    final controller = StreamController<bool>();
    final unsub = fsListenDoc('Users/$uid/activity/likes/images/$imageId', (String jsonStr) {
      controller.add(jsonDecode(jsonStr)['exists'] == true);
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchImageComments(String imageId) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    final unsub = fsListenQuery('artifacts/bqopd/public/data/comments', 'contentId', '==', jsonEncode(imageId), '', false, (String jsonStr) {
      final List decoded = jsonDecode(jsonStr);
      controller.add(decoded.map((d) {
        final data = d['data'] as Map<String, dynamic>;
        data['_id'] = d['id'];
        return data;
      }).toList());
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Future<void> addComment({required String imageId, required String text, String? fanzineId, String? fanzineTitle, String? displayName, String? username}) async {
    final uid = getCurrentUserId();
    if (uid == null || text.trim().isEmpty) return;

    await fsAddDoc('artifacts/bqopd/public/data/comments', jsonEncode({
      'contentId': imageId, 'userId': uid, 'text': text.trim(), 'createdAt': WebFieldValue.serverTimestamp(),
      'displayName': displayName, 'username': username, 'likeCount': 0,
      'context': {'fanzineId': fanzineId, 'fanzineTitle': fanzineTitle}
    }));

    if (imageId.isNotEmpty) {
      await fsUpdateDoc('images/$imageId', jsonEncode({'commentCount': WebFieldValue.increment(1)}));
    }
  }

  @override
  Future<void> deleteComment(String commentId, String imageId) async {
    await fsDeleteDoc('artifacts/bqopd/public/data/comments/$commentId');
    if (imageId.isNotEmpty) {
      await fsUpdateDoc('images/$imageId', jsonEncode({'commentCount': WebFieldValue.increment(-1)}));
    }
  }

  @override
  Future<void> toggleCommentLike(String commentId, bool isCurrentlyLiked) async {
    final uid = getCurrentUserId();
    if (uid == null) return;

    if (isCurrentlyLiked) {
      await fsUpdateDoc('artifacts/bqopd/public/data/comments/$commentId', jsonEncode({'likeCount': WebFieldValue.increment(-1)}));
      await fsDeleteDoc('Users/$uid/activity/likes/comments/$commentId');
    } else {
      await fsUpdateDoc('artifacts/bqopd/public/data/comments/$commentId', jsonEncode({'likeCount': WebFieldValue.increment(1)}));
      await fsSetDoc('Users/$uid/activity/likes/comments/$commentId', jsonEncode({'likedAt': WebFieldValue.serverTimestamp()}), true);
    }
  }

  @override
  Stream<bool> isCommentLiked(String commentId) {
    final uid = getCurrentUserId();
    if (uid == null) return Stream.value(false);
    final controller = StreamController<bool>();
    final unsub = fsListenDoc('Users/$uid/activity/likes/comments/$commentId', (String jsonStr) {
      controller.add(jsonDecode(jsonStr)['exists'] == true);
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Stream<bool> isFollowing(String targetUid) {
    final uid = getCurrentUserId();
    if (uid == null) return Stream.value(false);
    final controller = StreamController<bool>();
    final unsub = fsListenDoc('profiles/$uid/following/$targetUid', (String jsonStr) {
      controller.add(jsonDecode(jsonStr)['exists'] == true);
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Future<void> setFollowStatus(String targetUid, bool follow) async {
    final uid = getCurrentUserId();
    if (uid == null || uid == targetUid) return;

    if (follow) {
      await fsSetDoc('profiles/$uid/following/$targetUid', jsonEncode({'followedAt': WebFieldValue.serverTimestamp()}), true);
      await fsSetDoc('profiles/$targetUid/followers/$uid', jsonEncode({'followerAt': WebFieldValue.serverTimestamp()}), true);
      await fsUpdateDoc('profiles/$uid', jsonEncode({'followingCount': WebFieldValue.increment(1)}));
      await fsUpdateDoc('profiles/$targetUid', jsonEncode({'followerCount': WebFieldValue.increment(1)}));
    } else {
      await fsDeleteDoc('profiles/$uid/following/$targetUid');
      await fsDeleteDoc('profiles/$targetUid/followers/$uid');
      await fsUpdateDoc('profiles/$uid', jsonEncode({'followingCount': WebFieldValue.increment(-1)}));
      await fsUpdateDoc('profiles/$targetUid', jsonEncode({'followerCount': WebFieldValue.increment(-1)}));
    }
  }
}