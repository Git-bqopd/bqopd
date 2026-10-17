import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

/// Concrete web implementation of [IPipelineRepository] dispatching automated pipeline
/// tasks, OCR triggers, and 2000x3200 layout compilation to Cloud Functions via JS interop.
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
    required String fullText,
    String? ownerUserId,
    String templateId = 'basic_text',
    int startPageNumber = 1,
  }) async {
    final payload = {
      'fanzineId': fanzineId,
      'fullText': fullText,
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
    required String text,
    String? ownerUserId,
    String templateId = 'basic_text',
  }) async {
    final payload = {
      'fanzineId': fanzineId,
      'imageId': imageId,
      'text': text,
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