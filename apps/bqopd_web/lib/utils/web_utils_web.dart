import 'package:web/web.dart' as web;

/// Browser-specific implementation using package:web.
void scrollToElement(String id) {
  final el = web.document.getElementById(id);
  if (el != null) {
    el.scrollIntoView(web.ScrollIntoViewOptions(
      behavior: 'auto',
      block: 'start',
    ));
  }
}