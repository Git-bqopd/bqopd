import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import 'web_firebase_interop.dart';
import 'firebase_mocks.dart';
import 'unsaved_fanzine_registry.dart';

/// Centralized service to handle high-performance, client-side WebP layout
/// compilation and asset synchronization for template pages.
/// Decouples business and rendering rules from the UI panel views.
class PublisherCompiler {
  /// Compiles raw markdown text into three standardized WebP sizes using the
  /// browser canvas, uploads the binaries to Storage, and commits the records.
  static Future<Map<String, dynamic>> compileAndPublish({
    required String fanzineId,
    required String imageId,
    required String text,
  }) async {
    final uid = getCurrentUserId() ?? 'system_web';
    final updates = <String, dynamic>{};

    // 1. Resolve and replace image shortcodes with their absolute Firebase URLs
    final String compiledText = await resolveAndReplaceShortcodes(
      fanzineId,
      text,
    );

    // 2. Run the Web-based Canvas compiler for absolute layout accuracy
    final resultJson = await renderPublisherPage(compiledText);
    final decoded = jsonDecode(resultJson);

    final String origBase64 = decoded['original'];
    final String listBase64 = decoded['list'];
    final String gridBase64 = decoded['grid'];

    final origBytes = base64Decode(origBase64);
    final listBytes = base64Decode(listBase64);
    final gridBytes = base64Decode(gridBase64);

    final String baseDir = 'uploads/$uid/folio_assets/$fanzineId/$imageId';

    // 3. Upload three standard WebP sizes concurrently to Google Cloud Storage
    final urls = await Future.wait([
      stUpload('$baseDir/original.webp', origBytes, 'image/webp'),
      stUpload('$baseDir/list.webp', listBytes, 'image/webp'),
      stUpload('$baseDir/grid.webp', gridBytes, 'image/webp'),
    ]);

    // Force fresh URLs by appending a query timestamp to bypass browser caching
    final cb = DateTime.now().millisecondsSinceEpoch;
    final fileUrl = '${urls[0]}&cb=$cb';
    final listUrl = '${urls[1]}&cb=$cb';
    final gridUrl = '${urls[2]}&cb=$cb';

    updates['fileUrl'] = fileUrl;
    updates['listUrl'] = listUrl;
    updates['gridUrl'] = gridUrl;

    // 4. Synchronize parent fanzine page document models reactively
    if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
      final idx = pages.indexWhere((p) => p.imageId == imageId);
      if (idx != -1) {
        final p = pages[idx];
        pages[idx] = FanzinePage(
          id: p.id,
          pageNumber: p.pageNumber,
          imageId: p.imageId,
          imageUrl: fileUrl,
          gridUrl: gridUrl,
          listUrl: listUrl,
          storagePath: p.storagePath,
          status: 'ready',
          templateId: p.templateId,
          spreadPosition: p.spreadPosition,
          sidePreference: p.sidePreference,
          width: p.width,
          height: p.height,
        );
        UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(pages);
      }
    } else {
      final pagesRes = await fsQuery('fanzines/$fanzineId/pages', 'imageId', '==', jsonEncode(imageId), '');
      final List pageDocs = jsonDecode(pagesRes) as List;
      final List<Future<void>> pageUpdates = [];
      for (var pageDoc in pageDocs) {
        final pageId = pageDoc['id'] ?? '';
        if (pageId.isNotEmpty) {
          pageUpdates.add(
              fsUpdateDoc('fanzines/$fanzineId/pages/$pageId', jsonEncode({
                'imageUrl': fileUrl,
                'listUrl': listUrl,
                'gridUrl': gridUrl,
                'status': 'ready',
              }))
          );
        }
      }
      if (pageUpdates.isNotEmpty) {
        await Future.wait(pageUpdates);
      }
    }

    return updates;
  }
}