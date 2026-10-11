import 'dart:async';

/// Stub implementation for non-web environments (Server SSR / AOT VM).
/// Pure Dart signatures with zero browser/JS dependencies.

Future<String> renderMapCoverPage(String configJson) async {
  return '{}';
}

Future<String> renderPublisherPages(String text) async {
  return '[]';
}

Future<String> renderPublisherPage(String text) async {
  return '{}';
}

Future<String?> geocodeAddress(String address) async {
  return null;
}

Future<String> fnCall(String name, String dataStr) async {
  return '{}';
}

Future<void> loginWithFirebase(String email, String password) async {}

Future<void> registerWithFirebase(String email, String password, String username) async {}

Future<void> logoutFromFirebase() async {}

String? getCurrentUserId() => null;

String? getCurrentUserEmail() => null;

void onAuthStateChangedListener(void Function(String?, String?) callback) {}

Future<String> fsGetDoc(String path) async => '{"exists": false}';

dynamic fsListenDoc(String path, void Function(String) dartCallback) => null;

dynamic fsListenQuery(
    String path,
    String? field,
    String? op,
    String? valueJson,
    String? orderBy,
    bool? desc,
    void Function(String) dartCallback,
    ) => null;

Future<String> fsQuery(
    String path,
    String field,
    String op,
    String valueJson,
    String orderBy,
    ) async => '[]';

Future<void> fsUpdateDoc(String path, String dataStr) async {}

Future<void> fsSetDoc(String path, String dataStr, bool merge) async {}

Future<void> fsDeleteDoc(String path) async {}

Future<String> fsAddDoc(String path, String dataStr) async => '';

Future<String> stUpload(String path, List<int> bytes, String contentType) async => '';

Future<String> getPlacePredictions(String input) async => '[]';

void renderEntityMap(String containerId, String markersJson) {}

class WebFieldValue {
  static Map<String, dynamic> serverTimestamp() => {'__op': 'serverTimestamp'};
  static Map<String, dynamic> increment(num val) => {'__op': 'increment', 'value': val};
  static Map<String, dynamic> arrayUnion(List<dynamic> elements) => {'__op': 'arrayUnion', 'values': elements};
  static Map<String, dynamic> arrayRemove(List<dynamic> elements) => {'__op': 'arrayRemove', 'values': elements};
  static Map<String, dynamic> delete() => {'__op': 'delete'};
}