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
        final List<FanzinePage> updatedPages = List<FanzinePage>.from(pages);
        updatedPages[idx] = FanzinePage(
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
        UnsavedFanzineRegistry.pages[fanzineId] = updatedPages;
        UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(updatedPages);
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
    final imageQuery = await fsQuery('images', 'shortCode', '==', jsonEncode(shortcode), '');
    final List docs = jsonDecode(imageQuery);
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
      final List<FanzinePage> updatedPages = List<FanzinePage>.from(pages)..add(newPage);
      UnsavedFanzineRegistry.pages[fanzineId] = updatedPages;
      UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(updatedPages);
      return;
    }

    final resStr = await fsQuery('fanzines/$fanzineId/pages', '', '', '', '');
    final int nextNum = jsonDecode(resStr).length + 1;

    await fsSetDoc('fanzines/$fanzineId/pages/page_${DateTime.now().millisecondsSinceEpoch}', jsonEncode({
      'imageId': imageId, 'imageUrl': imageUrl, 'pageNumber': nextNum, 'status': 'ready',
      'width': width, 'height': height, 'createdAt': WebFieldValue.serverTimestamp(),
    }), true);
    await fsUpdateDoc('images/$imageId', jsonEncode({'usedInFanzines': WebFieldValue.arrayUnion([fanzineId])}));
  }

  @override
  Future<void> removePageFromFolio(String fanzineId, FanzinePage page, List<FanzinePage> allPages) async {
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      final List<FanzinePage> updatedPages = [];
      int currentNum = 1;
      for (var p in pages) {
        if (p.id != page.id) {
          updatedPages.add(FanzinePage(
            id: p.id,
            pageNumber: currentNum++,
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
          ));
        }
      }
      UnsavedFanzineRegistry.pages[fanzineId] = updatedPages;
      UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(updatedPages);
      return;
    }

    await fsDeleteDoc('fanzines/$fanzineId/pages/${page.id}');

    // Shift/Heal subsequent pages
    final leftPages = allPages.where((p) => p.id != page.id).toList();
    for (int i = 0; i < leftPages.length; i++) {
      final item = leftPages[i];
      final int expectedNum = i + 1;
      if (item.pageNumber != expectedNum) {
        await fsUpdateDoc('fanzines/$fanzineId/pages/${item.id}', jsonEncode({'pageNumber': expectedNum}));
      }
    }
  }

  @override
  Future<void> togglePageOrdering(String fanzineId, FanzinePage page, bool shouldOrder) async {
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      final idx = pages.indexWhere((p) => p.id == page.id);
      if (idx != -1) {
        final p = pages[idx];
        final List<FanzinePage> updatedPages = List<FanzinePage>.from(pages);
        updatedPages[idx] = FanzinePage(
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
        UnsavedFanzineRegistry.pages[fanzineId] = updatedPages;
        UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(updatedPages);
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

      final List<FanzinePage> updatedPages = List<FanzinePage>.from(pages);
      final temp = updatedPages[idx];
      updatedPages[idx] = updatedPages[targetIdx];
      updatedPages[targetIdx] = temp;

      for (int i = 0; i < updatedPages.length; i++) {
        final p = updatedPages[i];
        updatedPages[i] = FanzinePage(
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
      UnsavedFanzineRegistry.pages[fanzineId] = updatedPages;
      UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(updatedPages);
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

  @override
  Future<String> insertPublisherPage(String fanzineId, int afterPageNumber, String initialText, List<FanzinePage> allPages) async {
    final uid = getCurrentUserId() ?? 'system_web';
    final imageId = 'temp_pub_page_${DateTime.now().millisecondsSinceEpoch}';
    final pageId = 'page_${DateTime.now().millisecondsSinceEpoch}';
    final shortCode = ShortcodeGenerator.generateStandardCode();

    // COMPILE TO WEBP IMMEDIATELY: Ensure the page always resolves as an image from the moment of creation!
    String fileUrl = '';
    String listUrl = '';
    String gridUrl = '';

    try {
      final resultJson = await renderPublisherPage(initialText);
      final decoded = jsonDecode(resultJson);

      final String origBase64 = decoded['original'];
      final String listBase64 = decoded['list'];
      final String gridBase64 = decoded['grid'];

      final origBytes = base64Decode(origBase64);
      final listBytes = base64Decode(listBase64);
      final gridBytes = base64Decode(gridBase64);

      final String baseDir = 'uploads/$uid/folio_assets/$fanzineId/$imageId';

      final urls = await Future.wait([
        stUpload('$baseDir/original.webp', origBytes, 'image/webp'),
        stUpload('$baseDir/list.webp', listBytes, 'image/webp'),
        stUpload('$baseDir/grid.webp', gridBytes, 'image/webp'),
      ]);

      final cb = DateTime.now().millisecondsSinceEpoch;
      fileUrl = '${urls[0]}&cb=$cb';
      listUrl = '${urls[1]}&cb=$cb';
      gridUrl = '${urls[2]}&cb=$cb';
    } catch (e) {
      print('[insertPublisherPage WebP Compile Error] $e');
    }

    final imageMetadata = {
      'uid': uid,
      'uploaderId': uid,
      'type': 'template',
      'templateId': 'basic_text',
      'text': initialText,
      'text_corrected': initialText,
      'text_linked': initialText,
      'title': 'Generated Page',
      'isGenerated': true,
      'width': 2000,
      'height': 3200,
      'aspectRatio': 0.625,
      'is5x8': true,
      'shortCode': shortCode,
      'folioContext': fanzineId,
      'usedInFanzines': [fanzineId],
      if (fileUrl.isNotEmpty) 'fileUrl': fileUrl,
      if (listUrl.isNotEmpty) 'listUrl': listUrl,
      if (gridUrl.isNotEmpty) 'gridUrl': gridUrl,
    };

    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      // In-memory list operations
      final List<FanzinePage> currentPages = List.from(UnsavedFanzineRegistry.pages[fanzineId] ?? []);

      // Shift pageNumbers after insertion point
      for (int i = 0; i < currentPages.length; i++) {
        final p = currentPages[i];
        if (p.pageNumber > afterPageNumber) {
          currentPages[i] = FanzinePage(
            id: p.id,
            pageNumber: p.pageNumber + 1,
            imageId: p.imageId,
            imageUrl: p.imageUrl,
            gridUrl: p.gridUrl,
            listUrl: p.listUrl,
            status: p.status,
            templateId: p.templateId,
            spreadPosition: p.spreadPosition,
            sidePreference: p.sidePreference,
            width: p.width,
            height: p.height,
          );
        }
      }

      final newPage = FanzinePage(
        id: pageId,
        pageNumber: afterPageNumber + 1,
        imageId: imageId,
        imageUrl: fileUrl,
        gridUrl: gridUrl,
        listUrl: listUrl,
        status: 'ready',
        templateId: 'basic_text',
        width: 2000,
        height: 3200,
      );

      currentPages.insert(afterPageNumber, newPage);
      UnsavedFanzineRegistry.pages[fanzineId] = currentPages;
      // FIXED: Use getOrCreatePagesController to guarantee stream safety
      UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(currentPages);

      // Save simulated image document directly so standard queries can resolve it.
      await fsSetDoc('images/$imageId', jsonEncode(imageMetadata), true);
      return imageId;
    }

    // Persisted Firestore insertion
    await fsSetDoc('images/$imageId', jsonEncode(imageMetadata), true);

    // Shift subsequent pages in parallel
    final List<Future<void>> updates = [];
    for (final p in allPages) {
      if (p.pageNumber > afterPageNumber) {
        updates.add(fsUpdateDoc('fanzines/$fanzineId/pages/${p.id}', jsonEncode({'pageNumber': p.pageNumber + 1})));
      }
    }
    if (updates.isNotEmpty) {
      await Future.wait(updates);
    }

    await fsSetDoc('fanzines/$fanzineId/pages/$pageId', jsonEncode({
      'imageId': imageId,
      'imageUrl': fileUrl,
      'gridUrl': gridUrl,
      'listUrl': listUrl,
      'pageNumber': afterPageNumber + 1,
      'status': 'ready',
      'templateId': 'basic_text',
      'width': 2000,
      'height': 3200,
      'createdAt': WebFieldValue.serverTimestamp(),
    }), true);

    return imageId;
  }
}