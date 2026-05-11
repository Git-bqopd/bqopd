import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/firebase_mocks.dart';

class WebFanzineRepository implements IFanzineRepository {
  @override
  Stream<Fanzine> watchFanzineModel(String fanzineId) {
    final controller = StreamController<Fanzine>();
    final unsub = fsListenDoc('fanzines/$fanzineId', (String jsonStr) {
      final decoded = jsonDecode(jsonStr);
      final doc = WebDocumentSnapshot(decoded['path'], decoded['exists'], restoreTimestamps(decoded['data']));
      controller.add(Fanzine.fromFirestore(doc));
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Stream<List<FanzinePage>> watchPageModels(String fanzineId) {
    final controller = StreamController<List<FanzinePage>>();
    final unsub = fsListenQuery('fanzines/$fanzineId/pages', '', '', '', 'pageNumber', false, (String jsonStr) {
      final List decoded = jsonDecode(jsonStr);
      final pages = decoded.map((d) {
        final doc = WebDocumentSnapshot(d['path'], d['exists'], restoreTimestamps(d['data']));
        return FanzinePage.fromFirestore(doc);
      }).toList();
      controller.add(pages);
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Future<void> updateFanzine(String fanzineId, Map<String, dynamic> data) async {
    await fsUpdateDoc('fanzines/$fanzineId', jsonEncode(data));
  }

  @override
  Future<void> updatePageLayout(String fanzineId, FanzinePage page, String? spreadPosition, String sidePreference, List<FanzinePage> allPages) async {
    await fsUpdateDoc(page.reference.path, jsonEncode({
      'spreadPosition': spreadPosition,
      'sidePreference': sidePreference,
    }));
  }

  @override
  Future<void> addPageByShortcode(String fanzineId, String shortcode) async {
    final resStr = await fsQuery('images', 'shortCode', '==', jsonEncode(shortcode), '');
    final List docs = jsonDecode(resStr);
    if (docs.isEmpty) throw Exception('Image shortcode not found.');
    final doc = docs.first;
    final data = doc['data'];
    await addExistingImageToFolio(fanzineId, doc['id'], data['fileUrl'], width: data['width'], height: data['height']);
  }

  @override
  Future<void> addExistingImageToFolio(String fanzineId, String imageId, String imageUrl, {int? width, int? height}) async {
    final resStr = await fsQuery('fanzines/$fanzineId/pages', '', '', '', '');
    final int nextNum = jsonDecode(resStr).length + 1;

    await fsAddDoc('fanzines/$fanzineId/pages', jsonEncode({
      'imageId': imageId, 'imageUrl': imageUrl, 'pageNumber': nextNum, 'status': 'ready',
      'width': width, 'height': height, 'createdAt': WebFieldValue.serverTimestamp(),
    }));
    await fsUpdateDoc('images/$imageId', jsonEncode({'usedInFanzines': WebFieldValue.arrayUnion([fanzineId])}));
  }

  @override
  Future<void> removePageFromFolio(String fanzineId, FanzinePage page, List<FanzinePage> allPages) async {
    await fsDeleteDoc(page.reference.path);
  }

  @override
  Future<void> togglePageOrdering(String fanzineId, FanzinePage page, bool shouldOrder) async {
    await fsUpdateDoc(page.reference.path, jsonEncode({'pageNumber': shouldOrder ? 1 : 0}));
  }

  @override
  Future<void> reorderPageModel(String fanzineId, FanzinePage page, int delta, List<FanzinePage> allPages) async {
    await fsUpdateDoc(page.reference.path, jsonEncode({'pageNumber': page.pageNumber + delta}));
  }

  @override
  Future<void> deleteAssetCompletely(String fanzineId, String imageId, bool isDirectUpload) async {
    if (isDirectUpload) {
      await fsDeleteDoc('images/$imageId');
    }
  }

  @override
  Future<void> softPublish(String fanzineId) async {
    await fsUpdateDoc('fanzines/$fanzineId', jsonEncode({'isSoftPublished': true}));
  }
}