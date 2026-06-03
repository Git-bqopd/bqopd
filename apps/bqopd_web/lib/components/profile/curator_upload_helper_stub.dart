import 'dart:typed_data';

/// Fallback helper stub compiled safely on VM / Server-side Rendering environments.
class CuratorUploadHelper {
  static void pickAndUploadPdf({
    required void Function(String message) onStatus,
    required void Function(Uint8List bytes, String fileName) onUpload,
    required void Function(String errorMessage) onError,
  }) {
    // No-op on the Server
  }
}