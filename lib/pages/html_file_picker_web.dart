import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:async'; // Import for Completer

Future<Uint8List?> getFileFromFilePicker() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.click();
  final completer = Completer<Uint8List?>();

  input.onChange.listen((event) {
    final file = input.files?.first;
    if (file != null) {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoadEnd.listen((event) {
        completer.complete(reader.result as Uint8List?);
      });
    } else {
      completer.complete(null);
    }
  });

  return completer.future;
}