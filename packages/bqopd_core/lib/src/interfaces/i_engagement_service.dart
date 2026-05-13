abstract class IEngagementService {
  Future<void> toggleLike({
    required String imageId,
    required String? fanzineId,
    required bool isCurrentlyLiked,
  });

  Future<void> addComment({
    required String imageId,
    required String? fanzineId,
    required String? fanzineTitle,
    required String text,
    required String? displayName,
    required String? username,
    String? parentId,
  });

  Future<void> deleteComment(String commentId, String imageId);

  // Uses dynamic to avoid coupling pure Dart with cloud_firestore's QuerySnapshot
  Stream<dynamic> getCommentsStream(String imageId);

  Future<void> toggleCommentLike(String commentId, bool isCurrentlyLiked);

  Stream<bool> isCommentLikedStream(String commentId);

  Stream<bool> isLikedStream(String imageId);

  Future<void> followUser(String targetUid);

  Future<void> unfollowUser(String targetUid);

  Stream<bool> isFollowingStream(String targetUid);

  Future<void> toggleHashtag(String imageId, String tag, bool isVoting);
}