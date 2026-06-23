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

    // 1. Fetch user images first to map template shortcodes to absolute URLs
    List<Map<String, dynamic>> userImages = [];
    try {
      final imagesRes = await fsQuery('images', 'uploaderId', '==', jsonEncode(uid), '');
      final List decodedImages = jsonDecode(imagesRes) as List;
      userImages = decodedImages.map((d) {
        final data = d['data'] as Map<String, dynamic>;
        data['id'] = d['id'];
        return data;
      }).toList();
    } catch (_) {}

    // 2. Filter images belonging to this fanzine or folio context
    final folioImages = userImages.where((img) {
      final List usedIn = img['usedInFanzines'] ?? [];
      final String? contextId = img['folioContext'];
      return contextId == fanzineId || usedIn.contains(fanzineId);
    }).toList();

    // Sort by timestamp sequentially to align with reader indexes
    folioImages.sort((a, b) {
      final aT = a['timestamp'] ?? a['createdAt'] ?? '';
      final bT = b['timestamp'] ?? b['createdAt'] ?? '';
      return aT.toString().compareTo(bT.toString());
    });

    // 3. Create a map of shortcodes (img01, img02, etc.) to absolute URLs
    final Map<String, String> shortNameMap = {};
    for (int i = 0; i < folioImages.length; i++) {
      final img = folioImages[i];
      final String fileUrl = img['fileUrl'] ?? img['gridUrl'] ?? '';
      if (fileUrl.isNotEmpty) {
        final String shortName = "img${(i + 1).toString().padLeft(2, '0')}";
        shortNameMap[shortName] = fileUrl;
      }
    }

    // 4. Intercept and replace template shortcodes: {{1|img01|rowOffset|caption text}}
    // Supports both double brackets [[ ]] and double curly braces {{ }}
    String processedText = text;
    final templateRegex = RegExp(r'(?:\{\{|\[\[)(\d+)\|([^|]+)\|(.*?)(?:\}\}|\]\])');
    processedText = processedText.replaceAllMapped(templateRegex, (match) {
      final templateNum = match.group(1);
      final imgShortCode = match.group(2)?.trim() ?? '';
      final rest = match.group(3)?.trim() ?? '';

      var captionText = rest;
      String? rowOffset;

      // Check if the parameter starts with a row specifier, e.g. "20|text"
      final rowRegex = RegExp(r'^(\d+)\|(.*)$');
      final rowMatch = rowRegex.firstMatch(rest);
      if (rowMatch != null) {
        rowOffset = rowMatch.group(1);
        captionText = rowMatch.group(2)!.trim();
      }

      // Strip potential wrapping single or double quotes entered by user
      if ((captionText.startsWith("'") && captionText.endsWith("'")) ||
          (captionText.startsWith('"') && captionText.endsWith('"'))) {
        if (captionText.length >= 2) {
          captionText = captionText.substring(1, captionText.length - 1).trim();
        }
      }

      if (shortNameMap.containsKey(imgShortCode)) {
        final absoluteUrl = shortNameMap[imgShortCode];
        if (rowOffset != null) {
          return '{{TEMPLATE_$templateNum: $absoluteUrl | row=$rowOffset | $captionText}}';
        } else {
          return '{{TEMPLATE_$templateNum: $absoluteUrl | $captionText}}';
        }
      }
      return match.group(0)!; // Fallback to original text if missing
    });

    // 5. Resolve and replace any remaining standard image shortcodes (e.g. {{img01}})
    final String compiledText = await resolveAndReplaceShortcodes(
      fanzineId,
      processedText,
    );

    // 6. Run the Web-based Canvas compiler for absolute layout accuracy
    final resultJson = await renderPublisherPage(compiledText);
    final decoded = jsonDecode(resultJson);

    final String origBase64 = decoded['original'];
    final String listBase64 = decoded['list'];
    final String gridBase64 = decoded['grid'];

    final origBytes = base64Decode(origBase64);
    final listBytes = base64Decode(listBase64);
    final gridBytes = base64Decode(gridBase64);

    final String baseDir = 'uploads/$uid/folio_assets/$fanzineId/$imageId';

    // 7. Upload three standard WebP sizes concurrently to Google Cloud Storage
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

    // 8. Synchronize parent fanzine page document models reactively
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