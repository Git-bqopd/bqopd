enum ViewType { list, grid }

abstract class IViewService {
  Future<void> recordView({
    required String imageId,
    required String? pageId,
    required String fanzineId,
    required String fanzineTitle,
    required ViewType type,
  });

  // Uses dynamic to avoid coupling pure Dart with cloud_firestore's QuerySnapshot
  Stream<dynamic> getFanzinePagesStream(String fanzineId);
}