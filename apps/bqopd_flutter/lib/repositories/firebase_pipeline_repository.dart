import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Concrete Flutter implementation of [IPipelineRepository] that delegates OCR triggers,
/// pipeline processing, and 2000x3200 page rasterization to Firebase Cloud Functions.
class FirebasePipelineRepository implements IPipelineRepository {
  final FirebaseFunctions _functions;

  /// Creates a [FirebasePipelineRepository] instance with optional [FirebaseFunctions] injection.
  FirebasePipelineRepository({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  @override
  Future<void> triggerBatchOcr(String fanzineId) async {
    final callable = _functions.httpsCallable('trigger_batch_ocr');
    await callable.call({'fanzineId': fanzineId});
  }

  @override
  Future<void> triggerAiClean(String fanzineId) async {
    final callable = _functions.httpsCallable('trigger_ai_clean');
    await callable.call({'fanzineId': fanzineId});
  }

  @override
  Future<void> triggerGenerateLinks(String fanzineId) async {
    final callable = _functions.httpsCallable('trigger_generate_links');
    await callable.call({'fanzineId': fanzineId});
  }

  @override
  Future<void> rescanFanzine(String fanzineId) async {
    final callable = _functions.httpsCallable('rescan_fanzine');
    await callable.call({'fanzineId': fanzineId});
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

    final payload = <String, dynamic>{
      'fanzineId': fanzineId,
      'fullText': fullText,
      if (resolvedDisplayList != null) 'displayList': resolvedDisplayList,
      if (ownerUserId != null && ownerUserId.isNotEmpty) 'ownerUserId': ownerUserId,
      'templateId': templateId,
      'startPageNumber': startPageNumber,
    };

    final callable = _functions.httpsCallable(
      'compile_publisher_folio',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );

    final result = await callable.call(payload);
    if (result.data is Map) {
      return Map<String, dynamic>.from(result.data as Map);
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

    final payload = <String, dynamic>{
      'fanzineId': fanzineId,
      'imageId': imageId,
      'text': text,
      if (resolvedSheet != null) 'sheet': resolvedSheet,
      if (resolvedDisplayList != null) 'displayList': resolvedDisplayList,
      if (ownerUserId != null && ownerUserId.isNotEmpty) 'ownerUserId': ownerUserId,
      'templateId': templateId,
    };

    final callable = _functions.httpsCallable(
      'compile_publisher_page',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
    );

    final result = await callable.call(payload);
    if (result.data is Map) {
      return Map<String, dynamic>.from(result.data as Map);
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> compileMapCover(Map<String, dynamic> config) async {
    final callable = _functions.httpsCallable(
      'compile_map_cover',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
    );

    final result = await callable.call(config);
    if (result.data is Map) {
      return Map<String, dynamic>.from(result.data as Map);
    }
    return {};
  }
}