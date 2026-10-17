import 'dart:async';

/// Abstract interface defining automated pipeline execution tasks, OCR processing,
/// and backend layout compilation services across the bqopd platform.
/// Completely decoupled from Firebase or Flutter to maintain pure Dart compatibility.
abstract class IPipelineRepository {
  /// Triggers automated batch OCR transcription for all pages in a fanzine.
  Future<void> triggerBatchOcr(String fanzineId);

  /// Triggers AI typographical cleanup and entity detection across transcribed pages.
  Future<void> triggerAiClean(String fanzineId);

  /// Triggers automated wikilink bracket insertion and handle resolution.
  Future<void> triggerGenerateLinks(String fanzineId);

  /// Schedules a full rescan of a fanzine's source PDF and resets pipeline states.
  Future<void> rescanFanzine(String fanzineId);

  /// Compiles multi-page continuous markdown text into 2000x3200 publisher pages
  /// on the 42px baseline grid and streams multi-resolution WebP images to storage.
  Future<Map<String, dynamic>> compilePublisherFolio({
    required String fanzineId,
    required String fullText,
    String? ownerUserId,
    String templateId = 'basic_text',
    int startPageNumber = 1,
  });

  /// Re-compiles a single 2000x3200 publisher template page from markdown on the
  /// server and generates updated multi-resolution WebP image assets.
  Future<Map<String, dynamic>> compilePublisherPage({
    required String fanzineId,
    required String imageId,
    required String text,
    String? ownerUserId,
    String templateId = 'basic_text',
  });

  /// Generates a high-resolution illustrated 2000x3200 Google Maps cover page
  /// with radial pins and publication title on the server.
  Future<Map<String, dynamic>> compileMapCover(Map<String, dynamic> config);
}