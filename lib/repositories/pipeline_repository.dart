import 'package:cloud_functions/cloud_functions.dart';

/// Repository responsible for triggering the backend processing pipeline.
class PipelineRepository {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Step 1: Triggers batch OCR for a specific fanzine.
  Future<void> triggerBatchOcr(String fanzineId) async {
    await _functions.httpsCallable('trigger_batch_ocr').call({'fanzineId': fanzineId});
  }

  /// Step 2: Triggers Gemini to clean and format text
  Future<void> triggerAiClean(String fanzineId) async {
    await _functions.httpsCallable('trigger_ai_clean').call({'fanzineId': fanzineId});
  }

  /// Step 3: Triggers Gemini to find entities and link them
  Future<void> triggerGenerateLinks(String fanzineId) async {
    await _functions.httpsCallable('trigger_generate_links').call({'fanzineId': fanzineId});
  }

  /// Aggregates metadata to the top-level Fanzine doc.
  Future<Map<String, dynamic>> finalizeFanzineData(String fanzineId) async {
    final result = await _functions.httpsCallable('finalize_fanzine_data').call({'fanzineId': fanzineId});
    return Map<String, dynamic>.from(result.data);
  }

  /// Rescans a fanzine by nuking existing pages and re-extracting from source.
  Future<void> rescanFanzine(String fanzineId) async {
    await _functions.httpsCallable('rescan_fanzine').call({'fanzineId': fanzineId});
  }
}