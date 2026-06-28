/// No-op fallback implementation for the Dart VM (server-side context).
/// This prevents package:web from being compiled during server pre-rendering.
import 'dart:async';
import 'web_firebase_interop_stub.dart';

// EXPORT the stub relatively to align import resolution paths between compiler environments
export 'web_firebase_interop_stub.dart';

void scrollToElement(String id) {
  // No-op on the server
}

void readSelectedFile(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  // No-op on the server
}

void triggerFilePicker(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  // No-op on the server
}

/// Server VM stub for retrieving natural image dimensions.
Future<Map<String, int>> getImageDimensions(String objectUrl) async {
  return {'width': 0, 'height': 0};
}

/// Platform-safe stub for retrieving an input element value.
String getInputValue(dynamic event) {
  return '';
}

/// Server-side stub for redirecting legacy reader paths.
void redirectFanzinePath(dynamic context, String shortCode) {
  // No-op on the server
}

/// Platform-safe stub for saving a local preference.
void saveLocalPreference(String key, String value) {
  // No-op on the server
}

/// Platform-safe stub for retrieving a local preference.
String? getLocalPreference(String key) => null;

/// Server VM stub for opening URL links.
void openWindow(String url, String target) {
  // No-op on the server
}

/// Server VM stub for initializing Google Places Autocomplete.
void initAddressAutocomplete(String inputId, void Function(String) callback) {
  // No-op on the server
}