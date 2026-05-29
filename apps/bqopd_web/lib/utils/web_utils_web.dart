import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:async';

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

/// Reads the selected file from the DOM <input> element directly using pure Dart and package:web.
void readSelectedFile(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  final input = web.document.getElementById(inputId) as web.HTMLInputElement?;
  if (input == null) {
    print('[DART FILE READER] Input element with ID "$inputId" not found.');
    return;
  }
  final files = input.files;
  if (files == null || files.length == 0) {
    print('[DART FILE READER] No files chosen.');
    return;
  }
  final file = files.item(0);
  if (file == null) {
    print('[DART FILE READER] Selected file is null.');
    return;
  }

  print('[DART FILE READER] Loading: ${file.name} (${file.size} bytes)');

  final reader = web.FileReader();
  reader.onload = (web.Event event) {
    final result = reader.result;
    if (result == null) {
      print('[DART FILE READER] FileReader result is null.');
      return;
    }
// Result is a JSString when reading as DataURL
    final dataUrl = (result as JSString).toDart;
    final splitIndex = dataUrl.indexOf(',');
    if (splitIndex == -1) {
      print('[DART FILE READER] Invalid DataURL format.');
      return;
    }
    final base64 = dataUrl.substring(splitIndex + 1);
    final objectUrl = web.URL.createObjectURL(file);

    print('[DART FILE READER] Success. Triggering callback.');
    callback(base64, file.name, objectUrl);


  }.toJS;

  reader.onerror = (web.Event event) {
    print('[DART FILE READER] FileReader error encountered.');
  }.toJS;

  reader.readAsDataURL(file);
}

/// Creates or triggers a hidden native file input and monitors changes completely within Dart.
void triggerFilePicker(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  var input = web.document.getElementById(inputId) as web.HTMLInputElement?;
  if (input == null) {
    input = web.document.createElement('input') as web.HTMLInputElement
      ..id = inputId
      ..type = 'file'
      ..accept = 'image/*'
      ..style.display = 'none';
    web.document.body?.append(input);
  }

  input.onchange = (web.Event event) {
    readSelectedFile(inputId, callback);
  }.toJS;

  input.click();
}

/// Asynchronously loads an image object to extract its native width and height metrics on client.
Future<Map<String, int>> getImageDimensions(String objectUrl) {
  final completer = Completer<Map<String, int>>();
  final img = web.document.createElement('img') as web.HTMLImageElement;
  img.src = objectUrl;
  img.onload = (web.Event event) {
    completer.complete({
      'width': img.naturalWidth,
      'height': img.naturalHeight,
    });
  }.toJS;
  img.onerror = (web.Event event) {
    completer.complete({
      'width': 0,
      'height': 0,
    });
  }.toJS;
  return completer.future;
}

/// Client-side implementation of retrieving an input element value with type-safe casts.
String getInputValue(dynamic event) {
  if (event == null) return '';
  try {
    if (event is web.Event) {
      final target = event.target;
      if (target is web.HTMLInputElement) {
        return target.value;
      }
      if (target is web.HTMLTextAreaElement) {
        return target.value;
      }
    }
  } catch (e) {
    print('[getInputValue Error] $e');
  }
  return '';
}