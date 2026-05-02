abstract class IPipelineRepository {
  Future<void> triggerBatchOcr(String fanzineId);
  Future<void> triggerAiClean(String fanzineId);
  Future<void> triggerGenerateLinks(String fanzineId);
  Future<Map<String, dynamic>> finalizeFanzineData(String fanzineId);
  Future<void> rescanFanzine(String fanzineId);
}