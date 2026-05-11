import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

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
}