import 'package:cloud_functions/cloud_functions.dart';

class PipelineRepository {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<void> triggerBatchOcr(String fanzineId) async {
    await _functions.httpsCallable('trigger_batch_ocr').call({'fanzineId': fanzineId});
  }

  Future<void> triggerAiClean(String fanzineId) async {
    await _functions.httpsCallable('trigger_ai_clean').call({'fanzineId': fanzineId});
  }

  Future<void> triggerGenerateLinks(String fanzineId) async {
    await _functions.httpsCallable('trigger_generate_links').call({'fanzineId': fanzineId});
  }

  Future<Map<String, dynamic>> finalizeFanzineData(String fanzineId) async {
    final result = await _functions.httpsCallable('finalize_fanzine_data').call({'fanzineId': fanzineId});
    return Map<String, dynamic>.from(result.data);
  }

  Future<void> rescanFanzine(String fanzineId) async {
    await _functions.httpsCallable('rescan_fanzine').call({'fanzineId': fanzineId});
  }
}