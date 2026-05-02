import '../models/fanzine.dart';
import '../models/fanzine_page.dart';

abstract class IFanzineRepository {
  Stream<Fanzine?> watchFanzine(String fanzineId);
  Stream<List<FanzinePage>> watchPages(String fanzineId);

  Future<void> updateFanzine(String fanzineId, Map<String, dynamic> data);
  Future<void> updatePageLayout(String fanzineId, FanzinePage page, String? spreadPosition, String sidePreference, List<FanzinePage> allPages);
  Future<void> updatePageText(String fanzineId, String pageId, String text);

  Future<void> addExistingImageToFolio(String fanzineId, String imageId, String imageUrl, {int? width, int? height});
  Future<void> removePageFromFolio(String fanzineId, FanzinePage page, List<FanzinePage> allPages);
  Future<void> togglePageOrdering(String fanzineId, FanzinePage page, bool shouldOrder);
  Future<void> deleteAssetCompletely(String fanzineId, String imageId, bool isDirectUpload);
  Future<void> addPageByShortcode(String fanzineId, String shortcode);
  Future<void> reorderPageModel(String fanzineId, FanzinePage page, int delta, List<FanzinePage> allPages);

  Future<void> softPublish(String fanzineId);
  Future<Map<String, dynamic>?> checkHandleStatus(String handle);

  // Added for ProfileBloc delegations
  Future<void> deleteFolio(String fanzineId);
  Future<void> deleteImage(String imageId);
}