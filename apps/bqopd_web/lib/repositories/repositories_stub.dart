import 'dart:async';
import 'dart:typed_data';
import 'package:bqopd_core/bqopd_core.dart';

class StubAuthRepository implements IAuthRepository {
  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(null);
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> register({required String email, required String password, required String username}) async {}
  @override
  Future<void> logout() async {}
  @override
  AuthUser? get currentUser => null;
}

class StubFanzineRepository implements IFanzineRepository {
  @override
  Stream<Fanzine> watchFanzineModel(String fanzineId) => Stream.empty();
  @override
  Stream<List<FanzinePage>> watchPageModels(String fanzineId) => Stream.value([]);
  @override
  Future<void> updateFanzine(String fanzineId, Map<String, dynamic> data) async {}
  @override
  Future<void> updatePageLayout(String fanzineId, FanzinePage page, String? spreadPosition, String sidePreference, List<FanzinePage> allPages) async {}
  @override
  Future<void> addPageByShortcode(String fanzineId, String shortcode) async {}
  @override
  Future<void> addExistingImageToFolio(String fanzineId, String imageId, String imageUrl, {int? width, int? height}) async {}
  @override
  Future<void> removePageFromFolio(String fanzineId, FanzinePage page, List<FanzinePage> allPages) async {}
  @override
  Future<void> togglePageOrdering(String fanzineId, FanzinePage page, bool shouldOrder) async {}
  @override
  Future<void> reorderPageModel(String fanzineId, FanzinePage page, int delta, List<FanzinePage> allPages) async {}
  @override
  Future<void> deleteAssetCompletely(String fanzineId, String imageId, bool isDirectUpload) async {}
  @override
  Future<void> softPublish(String fanzineId) async {}
  @override
  Future<String> insertPublisherPage(String fanzineId, int afterPageNumber, String initialText, List<FanzinePage> allPages) async => '';
}

class StubEngagementRepository implements IEngagementRepository {
  @override
  Future<void> toggleImageLike({required String imageId, required String? fanzineId, required bool isCurrentlyLiked}) async {}
  @override
  Stream<bool> isImageLiked(String imageId) => Stream.value(false);
  @override
  Stream<List<Map<String, dynamic>>> watchImageComments(String imageId) => Stream.value([]);
  @override
  Future<void> addComment({required String imageId, required String text, String? fanzineId, String? fanzineTitle, String? displayName, String? username}) async {}
  @override
  Future<void> deleteComment(String commentId, String imageId) async {}
  @override
  Future<void> toggleCommentLike(String commentId, bool isCurrentlyLiked) async {}
  @override
  Stream<bool> isCommentLiked(String commentId) => Stream.value(false);
  @override
  Stream<bool> isFollowing(String targetUid) => Stream.value(false);
  @override
  Future<void> setFollowStatus(String targetUid, bool follow) async {}
}

class StubPipelineRepository implements IPipelineRepository {
  @override
  Future<void> triggerBatchOcr(String fanzineId) async {}
  @override
  Future<void> triggerAiClean(String fanzineId) async {}
  @override
  Future<void> triggerGenerateLinks(String fanzineId) async {}
  @override
  Future<void> rescanFanzine(String fanzineId) async {}
}

class StubUploadRepository implements IUploadRepository {
  @override
  Future<String> uploadBytes(Uint8List bytes, String path, String contentType) async => '';
  @override
  Future<void> saveImageMetadata(Map<String, dynamic> data) async {}
  @override
  Future<Map<String, dynamic>?> lookupUserByHandle(String handle) async => null;
}

class StubUserRepository implements IUserRepository {
  @override
  Stream<UserProfile?> watchUser(String uid) => Stream.value(null);
  @override
  Stream<UserAccount?> watchUserAccount(String uid) => Stream.value(null);
  @override
  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {}
  @override
  Stream<List<Map<String, dynamic>>> watchUserWorks(String uid) => Stream.value([]);
  @override
  Stream<List<Map<String, dynamic>>> watchUserMentions(String uid) => Stream.value([]);
  @override
  Future<String?> claimHandleForUser(String handle) async => null;
}

IAuthRepository createAuthRepository() => StubAuthRepository();
IFanzineRepository createFanzineRepository() => StubFanzineRepository();
IEngagementRepository createEngagementRepository() => StubEngagementRepository();
IPipelineRepository createPipelineRepository() => StubPipelineRepository();
IUploadRepository createUploadRepository() => StubUploadRepository();
IUserRepository createUserRepository() => StubUserRepository();