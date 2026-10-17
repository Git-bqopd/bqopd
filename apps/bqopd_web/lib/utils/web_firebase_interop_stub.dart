import 'dart:async';
import 'web_firebase_interop.dart';

/// Stub implementation for non-web environments (Server SSR / AOT VM).
/// Pure Dart signatures with zero browser/JS dependencies, matching the
/// exact public API surface of [web_firebase_interop_web.dart].

/// Non-web fallback subscription implementing [FirebaseSubscription] to safely
/// absorb cancellation callbacks without runtime null-check exceptions.
class StubSubscription implements FirebaseSubscription {
  @override
  void callAsFunction() {}
}

/// Stub for generating 2000x3200 map cover page on non-web environments.
Future<String> renderMapCoverPage(String configJson) async {
  return '{}';
}

/// Stub for generating multi-page publisher layouts on non-web environments.
Future<String> renderPublisherPages(String text) async {
  return '[]';
}

/// Stub for rendering a single publisher layout on non-web environments.
Future<String> renderPublisherPage(String text) async {
  return '{}';
}

/// Zero-pixel dry-run measurement stub returning 0 pages on non-web targets.
Future<int> measurePublisherPages(String text) async {
  return 0;
}

/// Stub for server-side verified address geocoding on non-web environments.
Future<String?> geocodeAddress(String address) async {
  return null;
}

/// Generic Cloud Function callable bridge stub.
Future<String> fnCall(String name, String dataStr) async {
  return '{}';
}

Future<void> loginWithFirebase(String email, String password) async {}

Future<void> registerWithFirebase(
    String email,
    String password,
    String username,
    ) async {}

Future<void> logoutFromFirebase() async {}

String? getCurrentUserId() => null;

String? getCurrentUserEmail() => null;

void onAuthStateChangedListener(void Function(String?, String?) callback) {}

Future<String> fsGetDoc(String path) async => '{"exists": false}';

FirebaseSubscription fsListenDoc(
    String path,
    void Function(String) dartCallback,
    ) =>
    StubSubscription();

FirebaseSubscription fsListenQuery(
    String path,
    String? field,
    String? op,
    String? valueJson,
    String? orderBy,
    bool? desc,
    void Function(String) dartCallback,
    ) =>
    StubSubscription();

Future<String> fsQuery(
    String path,
    String field,
    String op,
    String valueJson,
    String orderBy,
    ) async =>
    '[]';

Future<void> fsUpdateDoc(String path, String dataStr) async {}

Future<void> fsSetDoc(String path, String dataStr, bool merge) async {}

Future<void> fsDeleteDoc(String path) async {}

Future<String> fsAddDoc(String path, String dataStr) async => '';

Future<String> stUpload(
    String path,
    List<int> bytes,
    String contentType,
    ) async =>
    '';

void pickAndReadFile(
    String inputId,
    void Function(String base64, String fileName, String objectUrl) callback,
    ) {}

void readInputFile(
    String inputId,
    void Function(String base64, String fileName, String objectUrl) callback,
    ) {}

Future<String> getPlacePredictions(String input) async => '[]';

void renderEntityMap(String containerId, String markersJson) {}

class WebFieldValue {
  static Map<String, dynamic> serverTimestamp() => {'__op': 'serverTimestamp'};
  static Map<String, dynamic> increment(num val) => {
    '__op': 'increment',
    'value': val,
  };
  static Map<String, dynamic> arrayUnion(List<dynamic> elements) => {
    '__op': 'arrayUnion',
    'values': elements,
  };
  static Map<String, dynamic> arrayRemove(List<dynamic> elements) => {
    '__op': 'arrayRemove',
    'values': elements,
  };
  static Map<String, dynamic> delete() => {'__op': 'delete'};
}