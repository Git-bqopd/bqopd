import 'dart:typed_data';
import '../utils/web_firebase_interop.dart';

/// Server VM stub implementation of the static unsubscription handler.
class StubSubscription implements FirebaseSubscription {
  @override
  void callAsFunction() {}
}

/// Server VM stub for getting active auth IDs.
String? getCurrentUserId() => null;

/// Server VM stub for retrieving documents synchronously.
Future<String> fsGetDoc(String path) async => '{}';

/// Server VM stub for document snapshot listeners.
FirebaseSubscription fsListenDoc(String path, void Function(String) callback) => StubSubscription();

/// Server VM stub for query listeners.
FirebaseSubscription fsListenQuery(String path, String field, String op, String valueJson, String orderBy, bool desc, void Function(String) callback) => StubSubscription();

/// Server VM stub for doc updates.
Future<void> fsUpdateDoc(String path, String dataJson) async {}

/// Server VM stub for doc sets.
Future<void> fsSetDoc(String path, String dataJson, bool merge) async {}

/// Server VM stub for doc deletions.
Future<void> fsDeleteDoc(String path) async {}

/// Server VM stub for adding documents.
Future<String> fsAddDoc(String path, String dataJson) async => '';

/// Server VM stub for database queries.
Future<String> fsQuery(String path, String field, String op, String valueJson, String orderBy) async => '[]';

/// Server VM stub for function calls.
Future<String> fnCall(String name, String dataJson) async => '{}';

/// Server VM stub for media uploads.
Future<String> stUpload(String path, Uint8List bytes, String contentType) async => '';

/// Server VM stub for global authentication listener.
void onAuthStateChangedListener(void Function(String?, String?) callback) {}

/// Server VM stubs for Firebase top-level authentication functions.
Future<void> loginWithFirebase(String email, String password) async {}
Future<void> registerWithFirebase(String email, String password, String username) async {}
Future<void> logoutFromFirebase() async {}

/// Mock representation of WebFieldValue for the server environment.
class WebFieldValue {
  static Map<String, dynamic> serverTimestamp() => {};
  static Map<String, dynamic> increment(num value) => {};
  static Map<String, dynamic> arrayUnion(List values) => {};
  static Map<String, dynamic> arrayRemove(List values) => {};
  static Map<String, dynamic> delete() => {};
}