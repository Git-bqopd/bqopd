/// No-op fallback implementation for the Dart VM (server-side context).
/// This prevents package:web from being compiled during server pre-rendering.
void scrollToElement(String id) {
  // No-op on the server
}