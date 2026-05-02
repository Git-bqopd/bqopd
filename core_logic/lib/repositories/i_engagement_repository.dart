abstract class IEngagementRepository {
  Future<void> toggleImageLike({required String imageId, required String? fanzineId, required bool isCurrentlyLiked});
  Stream<bool> isImageLiked(String imageId);

  Stream<List<Map<String, dynamic>>> watchImageComments(String imageId);
  Future<void> addComment({required String imageId, required String text, String? fanzineId, String? fanzineTitle, String? displayName, String? username});
  Future<void> deleteComment(String commentId, String imageId);
  Future<void> toggleCommentLike(String commentId, bool isCurrentlyLiked);
  Stream<bool> isCommentLiked(String commentId);

  Stream<bool> isFollowing(String targetUid);
  Future<void> setFollowStatus(String targetUid, bool follow);
}