import 'dart:async';

// EXPORT the stub relatively to align import resolution paths between compiler environments
export 'web_firebase_interop_stub.dart';

void scrollToElement(String id, {String block = 'center', bool smooth = true}) {
  // No-op on the server
}

void scrollContainerToTop(String containerId, {bool smooth = true}) {
  // No-op on the server
}

void scrollContainerToBottom(String containerId, {bool smooth = true}) {
  // No-op on the server
}

void centerElementInContainer(String containerId, String targetId, {bool smooth = true}) {
  // No-op on the server
}

void scrollElementToTopOfContainer(
    String containerId,
    String targetId, {
      bool smooth = true,
      double offset = 16.0,
    }) {
  // No-op on the server
}

/// Server VM stub for calculating the active scroll item index.
int? calculateListScrollActiveIndex({
  required String containerId,
  required int totalItems,
  required String Function(int index) itemIdBuilder,
  double boundaryOffset = 15.0,
  double itemMargin = 16.0,
}) => null;

void copyToClipboard(String text) {
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

/// Server VM stub for retrieving the current browser location path.
String getCurrentPath() => '';

/// Server VM stub for mounting the Smartphone WebAR Tabletop viewport.
void mountTerminalWebAr({
  required String containerId,
  required String sceneJson,
  required void Function(String qrCode) onQrDetected,
  required void Function(int x, int y) onTileTapped,
}) {}

/// Server VM stub for updating the Smartphone WebAR Tabletop scene.
void updateTerminalWebArScene(String containerId, String sceneJson) {}

/// Server VM stub for toggling one-shot QR participant scan mode.
void setTerminalWebArScanMode(String containerId, bool enabled) {}

/// Server VM stub for disposing Smartphone WebAR camera & WebGL resources.
void disposeTerminalWebAr(String containerId) {}

/// Server VM stub for playing Razor's cyberpunk mixtape Web Audio loop.
void playTerminalMixtapeSynth(bool play) {}

/// Server VM stub for listening to scroll threshold.
void Function()? listenScrollThreshold({
  required String containerId,
  required double threshold,
  required void Function(bool isExceeded) onScroll,
}) => null;

/// Server VM stub for listening to sticky header scroll.
void Function()? listenStickyHeaderScroll({
  required String containerId,
  required String headerId,
  required void Function(bool isScrolled) onScroll,
}) => null;
