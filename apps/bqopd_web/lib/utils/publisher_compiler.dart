import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import 'web_firebase_interop.dart';
import 'firebase_mocks.dart';
import 'unsaved_fanzine_registry.dart';

/// Centralized service to handle high-performance WebP layout compilation,
/// zero-pixel page measurement, and asset synchronization for template pages.
/// Offloads heavy rasterization and Cloud Storage uploads to Cloud Functions
/// with automatic client-side fallback.
class PublisherCompiler {
  /// Prepares raw markdown text by expanding shorthand asset tags (e.g. {{1|img01|Caption}})
  /// and resolving wiki shortcodes to absolute URLs.
  static Future<String> prepareTextForCompilation({
    required String fanzineId,
    required String text,
  }) async {
    final uid = getCurrentUserId() ?? 'system_web';

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

    final folioImages = userImages.where((img) {
      final List usedIn = img['usedInFanzines'] ?? [];
      final String? contextId = img['folioContext'];
      return contextId == fanzineId || usedIn.contains(fanzineId);
    }).toList();

    folioImages.sort((a, b) {
      final aT = a['timestamp'] ?? a['createdAt'] ?? '';
      final bT = b['timestamp'] ?? b['createdAt'] ?? '';
      return aT.toString().compareTo(bT.toString());
    });

    final Map<String, String> shortNameMap = {};
    for (int i = 0; i < folioImages.length; i++) {
      final img = folioImages[i];
      final String fileUrl = img['fileUrl'] ?? img['gridUrl'] ?? '';
      if (fileUrl.isNotEmpty) {
        final String shortName = "img${(i + 1).toString().padLeft(2, '0')}";
        shortNameMap[shortName] = fileUrl;
      }
    }

    String processedText = text;
    final templateRegex = RegExp(r'(?:\{\{|\[\[)(\d+)\Vert{}([^\vert{}]+)\Vert{}(.*?)(?:\}\}\vert{}\]\])');
    processedText = processedText.replaceAllMapped(templateRegex, (match) {
      final templateNum = match.group(1);
      final imgShortCode = match.group(2)?.trim() ?? '';
      final rest = match.group(3)?.trim() ?? '';
      var captionText = rest;
      String? rowOffset;

      final rowRegex = RegExp(r'^(\d+)\|(.*)$');
      final rowMatch = rowRegex.firstMatch(rest);
      if (rowMatch != null) {
        rowOffset = rowMatch.group(1);
        captionText = rowMatch.group(2)!.trim();
      }

      if ((captionText.startsWith("'") && captionText.endsWith("'")) ||
          (captionText.startsWith('"') && captionText.endsWith('"'))) {
        if (captionText.length >= 2) {
          captionText = captionText.substring(1, captionText.length - 1).trim();
        }
      }

      if (shortNameMap.containsKey(imgShortCode)) {
        final absoluteUrl = shortNameMap[imgShortCode];
        if (rowOffset != null) {
          return '{{TEMPLATE_$templateNum:$absoluteUrl | row=$rowOffset \vert{}$captionText}}';
        } else {
          return '{{TEMPLATE_$templateNum: $absoluteUrl \vert{}$captionText}}';
        }
      }
      return match.group(0)!;
    });

    return await resolveAndReplaceShortcodes(
      fanzineId,
      processedText,
    );
  }

  /// Compiles a single 2000x3200 page from markdown.
  /// Calls the server-side Cloud Function `compile_publisher_page` by default,
  /// falling back to the browser canvas and client storage uploads if needed.
  static Future<Map<String, dynamic>> compileAndPublish({
    required String fanzineId,
    required String imageId,
    required String text,
    String templateId = 'basic_text',
  }) async {
    final uid = getCurrentUserId() ?? 'system_web';
    final updates = <String, dynamic>{};
    final templateDef = PageTemplateRegistry.getTemplate(templateId);
    final int templateWidth = templateDef?.width ?? 2000;
    final int templateHeight = templateDef?.height ?? 3200;

    final String compiledText = await prepareTextForCompilation(
      fanzineId: fanzineId,
      text: text,
    );

    String? fileUrl;
    String? listUrl;
    String? gridUrl;

    // 1. Primary: Server-side Cloud Function rasterization & storage upload
    try {
      final payload = {
        'fanzineId': fanzineId,
        'imageId': imageId,
        'text': compiledText,
        'ownerUserId': uid,
        'templateId': templateId,
      };
      final resStr = await fnCall('compile_publisher_page', jsonEncode(payload));
      final decoded = jsonDecode(resStr);
      if (decoded is Map && decoded['status'] == 'success') {
        fileUrl = decoded['fileUrl']?.toString();
        listUrl = decoded['listUrl']?.toString();
        gridUrl = decoded['gridUrl']?.toString();
      }
    } catch (e) {
      print('[PublisherCompiler compileAndPublish] Server callable error, falling back to client: $e');
    }

    // 2. Client-side fallback if server callable failed or offline
    if (fileUrl == null || listUrl == null || gridUrl == null) {
      final resultJson = await renderPublisherPage(compiledText);
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
    }

    updates['fileUrl'] = fileUrl;
    updates['listUrl'] = listUrl;
    updates['gridUrl'] = gridUrl;

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
          templateId: p.templateId ?? templateId,
          spreadPosition: p.spreadPosition,
          sidePreference: p.sidePreference,
          width: p.width ?? templateWidth,
          height: p.height ?? templateHeight,
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

  /// Quickly evaluates the exact baseline-grid page count for markdown text
  /// without allocating HTML5 canvas plates, downloading image assets, or encoding Base64 strings.
  static Future<int> measurePageCount({
    required String fanzineId,
    required String fullText,
  }) async {
    final String compiledText = await prepareTextForCompilation(
      fanzineId: fanzineId,
      text: fullText,
    );
    return await measurePublisherPages(compiledText);
  }

  /// Compiles a long markdown document into multiple connected 2000x3200 pages.
  /// Content flows seamlessly across columns and pages without arbitrary truncations.
  /// Calls `compile_publisher_folio` server-side on Cloud Functions, streaming WebPs
  /// directly to Storage and returning ready `FanzinePage` models.
  static Future<List<FanzinePage>> compileAndPublishMultiPage({
    required String fanzineId,
    required String fullText,
    String templateId = 'basic_text',
    int startPageNumber = 1,
    void Function(int pageIndex, int totalPages)? onProgress,
  }) async {
    final uid = getCurrentUserId() ?? 'system_web';
    final templateDef = PageTemplateRegistry.getTemplate(templateId);
    final int templateWidth = templateDef?.width ?? 2000;
    final int templateHeight = templateDef?.height ?? 3200;
    final double templateAspectRatio = templateDef?.aspectRatio ?? 0.625;

    final String compiledText = await prepareTextForCompilation(
      fanzineId: fanzineId,
      text: fullText,
    );

    // 1. Primary: Server-side Cloud Function bulk compilation & storage upload
    try {
      final payload = {
        'fanzineId': fanzineId,
        'fullText': compiledText,
        'ownerUserId': uid,
        'templateId': templateId,
        'startPageNumber': startPageNumber,
      };
      final resStr = await fnCall('compile_publisher_folio', jsonEncode(payload));
      final decoded = jsonDecode(resStr);
      if (decoded is Map && decoded['status'] == 'success' && decoded['pages'] is List) {
        final List pagesList = decoded['pages'];
        if (onProgress != null && pagesList.isNotEmpty) {
          onProgress(pagesList.length, pagesList.length);
        }
        return pagesList.map((p) {
          final Map<String, dynamic> pMap = Map<String, dynamic>.from(p as Map);
          return FanzinePage.fromMap(pMap['id']?.toString() ?? '', pMap);
        }).toList();
      }
    } catch (e) {
      print('[PublisherCompiler compileAndPublishMultiPage] Server callable error, falling back to client: $e');
    }

    // 2. Client-side fallback if server callable failed or offline
    final resultJson = await renderPublisherPages(compiledText);
    final List decodedPages = jsonDecode(resultJson) as List;

    if (decodedPages.isEmpty) {
      return [];
    }

    final List<FanzinePage> generatedPages = [];
    int pageNum = startPageNumber;

    for (int i = 0; i < decodedPages.length; i++) {
      if (onProgress != null) {
        onProgress(i + 1, decodedPages.length);
      }

      final pageData = decodedPages[i] as Map<String, dynamic>;
      final String origBase64 = pageData['original'];
      final String listBase64 = pageData['list'];
      final String gridBase64 = pageData['grid'];
      final String pageText = pageData['text'] ?? '';

      final origBytes = base64Decode(origBase64);
      final listBytes = base64Decode(listBase64);
      final gridBytes = base64Decode(gridBase64);

      final pageImageId = 'folio_text_page_${DateTime.now().millisecondsSinceEpoch}_$pageNum';
      final pageShortCode = ShortcodeGenerator.generateStandardCode();
      final String baseDir = 'uploads/$uid/folio_assets/$fanzineId/$pageImageId';

      final urls = await Future.wait([
        stUpload('$baseDir/original.webp', origBytes, 'image/webp'),
        stUpload('$baseDir/list.webp', listBytes, 'image/webp'),
        stUpload('$baseDir/grid.webp', gridBytes, 'image/webp'),
      ]);

      final cb = DateTime.now().millisecondsSinceEpoch;
      final fileUrl = '${urls[0]}&cb=$cb';
      final listUrl = '${urls[1]}&cb=$cb';
      final gridUrl = '${urls[2]}&cb=$cb';

      final imageMetadata = {
        'uid': uid,
        'uploaderId': uid,
        'type': 'template',
        'templateId': templateId,
        'text': pageText,
        'text_corrected': pageText,
        'text_linked': pageText,
        'title': 'Letters Page $pageNum',
        'isGenerated': true,
        'width': templateWidth,
        'height': templateHeight,
        'aspectRatio': templateAspectRatio,
        'is5x8': true,
        'shortCode': pageShortCode,
        'folioContext': fanzineId,
        'usedInFanzines': [fanzineId],
        'fileUrl': fileUrl,
        'listUrl': listUrl,
        'gridUrl': gridUrl,
      };
      await fsSetDoc('images/$pageImageId', jsonEncode(imageMetadata), true);

      generatedPages.add(FanzinePage(
        id: 'page_${DateTime.now().millisecondsSinceEpoch}_$pageNum',
        pageNumber: pageNum,
        imageId: pageImageId,
        imageUrl: fileUrl,
        gridUrl: gridUrl,
        listUrl: listUrl,
        status: 'ready',
        templateId: templateId,
        width: templateWidth,
        height: templateHeight,
        is5x8: true,
      ));
      pageNum++;
    }

    return generatedPages;
  }
}