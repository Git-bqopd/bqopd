/// No-op fallback implementation for the Dart VM (server-side context).
/// This prevents package:web from being compiled during server pre-rendering.
void scrollToElement(String id) {
  // No-op on the server
}

void readSelectedFile(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  // No-op on the server
}

void triggerFilePicker(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  // No-op on the server
}