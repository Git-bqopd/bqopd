import 'package:cloud_functions/cloud_functions.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Concrete Firebase implementation of the IPipelineRepository interface.
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
}