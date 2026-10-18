import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

/// Concrete web implementation of [IPipelineRepository] dispatching automated pipeline
/// tasks, OCR triggers, and 2000x3200 layout compilation to Cloud Functions via JS interop.
/// Supports both legacy continuous markdown text and deterministic [PageDisplayList] command trees.
class WebPipelineRepository implements IPipelineRepository {
  @override
  Future<void> triggerBatchOcr(String fanzineId) async {
    await fnCall('trigger_batch_ocr', jsonEncode({'fanzineId': fanzineId}));
  }

  @override
  Future<void> triggerAiClean(String fanzineId) async {
    await fnCall('trigger_ai_clean', jsonEncode({'fanzineId': fanzineId}));
  }

  @override
  Future<void> triggerGenerateLinks(String fanzineId) async {
    await fnCall('trigger_generate_links', jsonEncode({'fanzineId': fanzineId}));
  }

  @override
  Future<void> rescanFanzine(String fanzineId) async {
    await fnCall('rescan_fanzine', jsonEncode({'fanzineId': fanzineId}));
  }

  @override
  Future<Map<String, dynamic>> compilePublisherFolio({
    required String fanzineId,
    String fullText = '',
    dynamic displayList,
    String? ownerUserId,
    String templateId = 'basic_text',
    int startPageNumber = 1,
  }) async {
    dynamic resolvedDisplayList;
    if (displayList is PageDisplayList) {
      resolvedDisplayList = displayList.toMap();
    } else if (displayList is Map) {
      resolvedDisplayList = Map<String, dynamic>.from(displayList);
    } else if (displayList is String) {
      resolvedDisplayList = displayList;
    }

    final payload = {
      'fanzineId': fanzineId,
      'fullText': fullText,
      if (resolvedDisplayList != null) 'displayList': resolvedDisplayList,
      if (ownerUserId != null && ownerUserId.isNotEmpty) 'ownerUserId': ownerUserId,
      'templateId': templateId,
      'startPageNumber': startPageNumber,
    };

    final resStr = await fnCall('compile_publisher_folio', jsonEncode(payload));
    if (resStr.isNotEmpty && resStr != 'null') {
      final decoded = jsonDecode(resStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> compilePublisherPage({
    required String fanzineId,
    required String imageId,
    String text = '',
    dynamic sheet,
    dynamic displayList,
    String? ownerUserId,
    String templateId = 'basic_text',
  }) async {
    dynamic resolvedSheet;
    if (sheet is PageLayoutSheet) {
      resolvedSheet = sheet.toMap();
    } else if (sheet is Map) {
      resolvedSheet = Map<String, dynamic>.from(sheet);
    } else if (sheet is String) {
      resolvedSheet = sheet;
    }

    dynamic resolvedDisplayList;
    if (displayList is PageDisplayList) {
      resolvedDisplayList = displayList.toMap();
    } else if (displayList is Map) {
      resolvedDisplayList = Map<String, dynamic>.from(displayList);
    } else if (displayList is String) {
      resolvedDisplayList = displayList;
    }

    final payload = {
      'fanzineId': fanzineId,
      'imageId': imageId,
      'text': text,
      if (resolvedSheet != null) 'sheet': resolvedSheet,
      if (resolvedDisplayList != null) 'displayList': resolvedDisplayList,
      if (ownerUserId != null && ownerUserId.isNotEmpty) 'ownerUserId': ownerUserId,
      'templateId': templateId,
    };

    final resStr = await fnCall('compile_publisher_page', jsonEncode(payload));
    if (resStr.isNotEmpty && resStr != 'null') {
      final decoded = jsonDecode(resStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> compileMapCover(Map<String, dynamic> config) async {
    final resStr = await fnCall('compile_map_cover', jsonEncode(config));
    if (resStr.isNotEmpty && resStr != 'null') {
      final decoded = jsonDecode(resStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return {};
  }
}