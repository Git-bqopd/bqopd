import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:async';
import 'dart:js_util' as js_util;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

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

/// Reads the selected file from the DOM  element directly using pure Dart and package:web.
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
/// Registers event listeners before assigning the source to eliminate race conditions.
Future<Map<String, int>> getImageDimensions(String objectUrl) {
  final completer = Completer<Map<String, int>>();
  final img = web.document.createElement('img') as web.HTMLImageElement;
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
  img.src = objectUrl;
  return completer.future;
}

/// Client-side implementation of retrieving an input element value with type-safe casts.
/// Leverages a robust multi-tier fallback to seamlessly bridge new JS interop and legacy types.
String getInputValue(dynamic event) {
  if (event == null) return '';
// 1. Try modern js_util property access (highly robust, works on raw JS objects, JSObjects, and native browser Events)
  try {
    if (js_util.hasProperty(event, 'target')) {
      final target = js_util.getProperty(event, 'target');
      if (target != null && js_util.hasProperty(target, 'value')) {
        final val = js_util.getProperty(target, 'value');
        if (val != null) {
          return val.toString();
        }
      }
    }
  } catch (e) {
    print('[getInputValue js_util Error] $e');
  }
// 2. Fallback to dynamic property invocation (handles legacy dart:html or wrapped event variants)
  try {
    final target = (event as dynamic).target;
    if (target != null) {
      final val = target.value;
      if (val != null) {
        return val.toString();
      }
    }
  } catch (e) {
    print('[getInputValue dynamic Fallback Error] $e');
  }
// 3. Fallback to package:web extension type matching
  try {
    if (event is web.Event) {
      final target = event.target;
      if (target != null) {
        final input = target as web.HTMLInputElement;
        return input.value;
      }
    }
  } catch (_) {}
  return '';
}

/// Checks the current browser URL path and performs a client-side route replacement
/// to the vanity url if accessed via the legacy /reader/:fanzineId route.
void redirectFanzinePath(dynamic context, String shortCode) {
  try {
    final currentPath = web.window.location.pathname;
    if (currentPath.startsWith('/reader/') && context is BuildContext) {
      Router.of(context).replace('/$shortCode');
    }
  } catch (e) {
    print('[redirectFanzinePath Error] $e');
  }
}

/// Browser-specific preference saving using package:web.
void saveLocalPreference(String key, String value) {
  web.window.localStorage.setItem(key, value);
}

/// Browser-specific preference retrieval using package:web.
String? getLocalPreference(String key) {
  return web.window.localStorage.getItem(key);
}