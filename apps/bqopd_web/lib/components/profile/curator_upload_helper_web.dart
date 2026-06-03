import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// High-fidelity web interop execution library safely compiled only for Browser runtimes.
class CuratorUploadHelper {
  static void pickAndUploadPdf({
    required void Function(String message) onStatus,
    required void Function(Uint8List bytes, String fileName) onUpload,
    required void Function(String errorMessage) onError,
  }) {
    final web.HTMLInputElement input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'file';
    input.accept = '.pdf';
    input.style.display = 'none';
    web.document.body?.append(input);

    input.onchange = (web.Event event) {
      final files = input.files;
      if (files == null || files.length == 0) return;
      final file = files.item(0);
      if (file == null) return;

      onStatus('Reading "${file.name}"...');

      final reader = web.FileReader();
      reader.onload = (web.Event e) {
        try {
          final result = reader.result;
          if (result == null) {
            onError("Could not read chosen file.");
            return;
          }

          final dataUrl = (result as JSString).toDart;
          final splitIndex = dataUrl.indexOf(',');
          final base64 = dataUrl.substring(splitIndex + 1);
          final bytes = base64Decode(base64);

          onUpload(bytes, file.name);
        } catch (err) {
          onError(err.toString());
        }
      }.toJS;

      reader.readAsDataURL(file);
    }.toJS;

    input.click();
    input.remove(); // Clean up from DOM
  }
}