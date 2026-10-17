import 'package:cloud_functions/cloud_functions.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Concrete Firebase implementation of the [IPipelineRepository] interface for Flutter.
/// Connects automated OCR tasks, typographical cleaning, and server-side layout
/// generation to Cloud Functions via the native Firebase Functions SDK.
class FirebasePipelineRepository implements IPipelineRepository {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<void> triggerBatchOcr(String fanzineId) async {
    await _functions.httpsCallable('trigger_batch_ocr').call({'fanzineId': fanzineId});
  }

  @override
  Future<void> triggerAiClean(String fanzineId) async {
    await _functions.httpsCallable('trigger_ai_clean').call({'fanzineId': fanzineId});
  }

  @override
  Future<void> triggerGenerateLinks(String fanzineId) async {
    await _functions.httpsCallable('trigger_generate_links').call({'fanzineId': fanzineId});
  }

  @override
  Future<void> rescanFanzine(String fanzineId) async {
    await _functions.httpsCallable('rescan_fanzine').call({'fanzineId': fanzineId});
  }

  @override
  Future<Map<String, dynamic>> compilePublisherFolio({
    required String fanzineId,
    required String fullText,
    String? ownerUserId,
    String templateId = 'basic_text',
    int startPageNumber = 1,
  }) async {
    final result = await _functions.httpsCallable('compile_publisher_folio').call({
      'fanzineId': fanzineId,
      'fullText': fullText,
      if (ownerUserId != null && ownerUserId.isNotEmpty) 'ownerUserId': ownerUserId,
      'templateId': templateId,
      'startPageNumber': startPageNumber,
    });
    if (result.data is Map) {
      return Map<String, dynamic>.from(result.data as Map);
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
    final result = await _functions.httpsCallable('compile_publisher_page').call({
      'fanzineId': fanzineId,
      'imageId': imageId,
      'text': text,
      if (ownerUserId != null && ownerUserId.isNotEmpty) 'ownerUserId': ownerUserId,
      'templateId': templateId,
    });
    if (result.data is Map) {
      return Map<String, dynamic>.from(result.data as Map);
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> compileMapCover(Map<String, dynamic> config) async {
    final result = await _functions.httpsCallable('compile_map_cover').call(config);
    if (result.data is Map) {
      return Map<String, dynamic>.from(result.data as Map);
    }
    return {};
  }
}