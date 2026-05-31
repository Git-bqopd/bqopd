import '../models/fanzine.dart';
import '../models/fanzine_page.dart';

abstract class IFanzineRepository {
  Stream<Fanzine> watchFanzineModel(String fanzineId);
  Stream<List<FanzinePage>> watchPageModels(String fanzineId);
  Future<void> updateFanzine(String fanzineId, Map<String, dynamic> data);
  Future<void> updatePageLayout(String fanzineId, FanzinePage page, String? spreadPosition, String sidePreference, List<FanzinePage> allPages);
  Future<void> addPageByShortcode(String fanzineId, String shortcode);
  Future<void> addExistingImageToFolio(String fanzineId, String imageId, String imageUrl, {int? width, int? height});
  Future<void> removePageFromFolio(String fanzineId, FanzinePage page, List<FanzinePage> allPages);
  Future<void> togglePageOrdering(String fanzineId, FanzinePage page, bool shouldOrder);
  Future<void> reorderPageModel(String fanzineId, FanzinePage page, int delta, List<FanzinePage> allPages);
  Future<void> deleteAssetCompletely(String fanzineId, String imageId, bool isDirectUpload);
  Future<void> softPublish(String fanzineId);

  /// Inserts a newly generated 2000x3200 publisher template page immediately in-order.
  Future<String> insertPublisherPage(String fanzineId, int afterPageNumber, String initialText, List<FanzinePage> allPages);
}