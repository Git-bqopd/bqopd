import 'dart:async';
import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/firebase_mocks.dart';
import '../utils/unsaved_fanzine_registry.dart';

class WebFanzineRepository implements IFanzineRepository {
  @override
  Stream<Fanzine> watchFanzineModel(String fanzineId) {
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      return UnsavedFanzineRegistry.getOrCreateFanzineController(fanzineId).stream.cast<Fanzine>();
    }

    final controller = StreamController<Fanzine>();
    final unsub = fsListenDoc('fanzines/$fanzineId', (String jsonStr) {
      final decoded = jsonDecode(jsonStr);
      if (decoded['exists'] == true) {
        controller.add(Fanzine.fromMap(decoded['id'], restoreTimestamps(decoded['data'])));
      }
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Stream<List<FanzinePage>> watchPageModels(String fanzineId) {
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      return UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).stream.cast<List<FanzinePage>>();
    }

    final controller = StreamController<List<FanzinePage>>();
    final unsub = fsListenQuery('fanzines/$fanzineId/pages', '', '', '', 'pageNumber', false, (String jsonStr) {
      final List decoded = jsonDecode(jsonStr);
      final pages = decoded.map((d) {
        return FanzinePage.fromMap(d['id'], restoreTimestamps(d['data']));
      }).toList();
      controller.add(pages);
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Future<void> updateFanzine(String fanzineId, Map<String, dynamic> data) async {
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      return;
    }
    await fsUpdateDoc('fanzines/$fanzineId', jsonEncode(data));
  }

  @override
  Future<void> updatePageLayout(String fanzineId, FanzinePage page, String? spreadPosition, String sidePreference, List<FanzinePage> allPages) async {
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      final idx = pages.indexWhere((p) => p.id == page.id);
      if (idx != -1) {
        pages[idx] = FanzinePage(
          id: page.id,
          pageNumber: page.pageNumber,
          imageId: page.imageId,
          imageUrl: page.imageUrl,
          gridUrl: page.gridUrl,
          listUrl: page.listUrl,
          storagePath: page.storagePath,
          status: page.status,
          templateId: page.templateId,
          spreadPosition: spreadPosition,
          sidePreference: sidePreference,
          width: page.width,
          height: page.height,
        );
        UnsavedFanzineRegistry.pagesControllers[fanzineId]?.add(pages);
      }
      return;
    }

    await fsUpdateDoc('fanzines/$fanzineId/pages/${page.id}', jsonEncode({
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
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      final nextNum = pages.length + 1;
      final newPage = FanzinePage(
        id: 'page_${DateTime.now().millisecondsSinceEpoch}_${pages.length}',
        pageNumber: nextNum,
        imageId: imageId,
        imageUrl: imageUrl,
        status: 'ready',
        width: width,
        height: height,
      );
      pages.add(newPage);
      UnsavedFanzineRegistry.pagesControllers[fanzineId]?.add(pages);
      return;
    }

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
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      pages.removeWhere((p) => p.id == page.id);
      for (int i = 0; i < pages.length; i++) {
        final p = pages[i];
        pages[i] = FanzinePage(
          id: p.id,
          pageNumber: i + 1,
          imageId: p.imageId,
          imageUrl: p.imageUrl,
          gridUrl: p.gridUrl,
          listUrl: p.listUrl,
          storagePath: p.storagePath,
          status: p.status,
          templateId: p.templateId,
          spreadPosition: p.spreadPosition,
          sidePreference: p.sidePreference,
          width: p.width,
          height: p.height,
        );
      }
      UnsavedFanzineRegistry.pagesControllers[fanzineId]?.add(pages);
      return;
    }

    await fsDeleteDoc('fanzines/$fanzineId/pages/${page.id}');
  }

  @override
  Future<void> togglePageOrdering(String fanzineId, FanzinePage page, bool shouldOrder) async {
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      final idx = pages.indexWhere((p) => p.id == page.id);
      if (idx != -1) {
        final p = pages[idx];
        pages[idx] = FanzinePage(
          id: p.id,
          pageNumber: shouldOrder ? 1 : 0,
          imageId: p.imageId,
          imageUrl: p.imageUrl,
          gridUrl: p.gridUrl,
          listUrl: p.listUrl,
          storagePath: p.storagePath,
          status: p.status,
          templateId: p.templateId,
          spreadPosition: p.spreadPosition,
          sidePreference: p.sidePreference,
          width: p.width,
          height: p.height,
        );
        UnsavedFanzineRegistry.pagesControllers[fanzineId]?.add(pages);
      }
      return;
    }

    await fsUpdateDoc('fanzines/$fanzineId/pages/${page.id}', jsonEncode({'pageNumber': shouldOrder ? 1 : 0}));
  }

  @override
  Future<void> reorderPageModel(String fanzineId, FanzinePage page, int delta, List<FanzinePage> allPages) async {
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      final idx = pages.indexWhere((p) => p.id == page.id);
      if (idx == -1) return;

      final targetIdx = idx + delta;
      if (targetIdx < 0 || targetIdx >= pages.length) return;

      final temp = pages[idx];
      pages[idx] = pages[targetIdx];
      pages[targetIdx] = temp;

      for (int i = 0; i < pages.length; i++) {
        final p = pages[i];
        pages[i] = FanzinePage(
          id: p.id,
          pageNumber: i + 1,
          imageId: p.imageId,
          imageUrl: p.imageUrl,
          gridUrl: p.gridUrl,
          listUrl: p.listUrl,
          storagePath: p.storagePath,
          status: p.status,
          templateId: p.templateId,
          spreadPosition: p.spreadPosition,
          sidePreference: p.sidePreference,
          width: p.width,
          height: p.height,
        );
      }
      UnsavedFanzineRegistry.pagesControllers[fanzineId]?.add(pages);
      return;
    }

    await fsUpdateDoc('fanzines/$fanzineId/pages/${page.id}', jsonEncode({'pageNumber': page.pageNumber + delta}));
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