@JS()
library web_firebase_interop_web;

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:js_util' as js_util;
import '../utils/web_firebase_interop.dart';

/// Web implementation of the subscription wrapper to bridge the JS unsubscription callback.
class WebSubscription implements FirebaseSubscription {
  final JSFunction _jsFunction;
  WebSubscription(this._jsFunction);

  @override
  void callAsFunction() {
    _jsFunction.callAsFunction();
  }
}

@JS('getCurrentUserId')
external JSString? _getCurrentUserId();
String? getCurrentUserId() => _getCurrentUserId()?.toDart;

@JS('fsGetDoc')
external JSPromise _fsGetDoc(JSString path);
Future<String> fsGetDoc(String path) async {
  final jsRes = await _fsGetDoc(path.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('fsListenDoc')
external JSFunction _fsListenDoc(JSString path, JSFunction callback);

FirebaseSubscription fsListenDoc(String path, void Function(String) callback) {
  final jsFunc = _fsListenDoc(path.toJS, ((JSString str) => callback(str.toDart)).toJS);
  return WebSubscription(jsFunc);
}

@JS('fsListenQuery')
external JSFunction _fsListenQuery(JSString path, JSString field, JSString op, JSString valueJson, JSString orderBy, JSBoolean desc, JSFunction callback);

FirebaseSubscription fsListenQuery(String path, String field, String op, String valueJson, String orderBy, bool desc, void Function(String) callback) {
  final jsFunc = _fsListenQuery(path.toJS, field.toJS, op.toJS, valueJson.toJS, orderBy.toJS, desc.toJS, ((JSString str) => callback(str.toDart)).toJS);
  return WebSubscription(jsFunc);
}

@JS('fsUpdateDoc')
external JSPromise _fsUpdateDoc(JSString path, JSString dataJson);
Future<void> fsUpdateDoc(String path, String dataJson) async {
  await _fsUpdateDoc(path.toJS, dataJson.toJS).toDart;
}

@JS('fsSetDoc')
external JSPromise _fsSetDoc(JSString path, JSString dataJson, JSBoolean merge);
Future<void> fsSetDoc(String path, String dataJson, bool merge) async {
  await _fsSetDoc(path.toJS, dataJson.toJS, merge.toJS).toDart;
}

@JS('fsDeleteDoc')
external JSPromise _fsDeleteDoc(JSString path);
Future<void> fsDeleteDoc(String path) async {
  await _fsDeleteDoc(path.toJS).toDart;
}

@JS('fsAddDoc')
external JSPromise _fsAddDoc(JSString path, JSString dataJson);
Future<String> fsAddDoc(String path, String dataJson) async {
  final jsRes = await _fsAddDoc(path.toJS, dataJson.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('fsQuery')
external JSPromise _fsQuery(JSString path, JSString field, JSString op, JSString valueJson, JSString orderBy);
Future<String> fsQuery(String path, String field, String op, String valueJson, String orderBy) async {
  final jsRes = await _fsQuery(path.toJS, field.toJS, op.toJS, valueJson.toJS, orderBy.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('fnCall')
external JSPromise _fnCall(JSString name, JSString dataJson);
Future<String> fnCall(String name, String dataJson) async {
  final jsRes = await _fnCall(name.toJS, dataJson.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('stUpload')
external JSPromise _stUpload(JSString path, JSUint8Array bytes, JSString contentType);
Future<String> stUpload(String path, Uint8List bytes, String contentType) async {
  final jsRes = await _stUpload(path.toJS, bytes.toJS, contentType.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('onAuthStateChangedListener')
external void _onAuthStateChangedListener(JSFunction callback);

void onAuthStateChangedListener(void Function(String?, String?) callback) {
  _onAuthStateChangedListener(((JSString? uid, JSString? email) {
    callback(uid?.toDart, email?.toDart);
  }).toJS);
}

@JS('loginWithFirebase')
external JSPromise _loginWithFirebase(JSString email, JSString password);
Future<void> loginWithFirebase(String email, String password) async {
  await _loginWithFirebase(email.toJS, password.toJS).toDart;
}

@JS('registerWithFirebase')
external JSPromise _registerWithFirebase(JSString email, JSString password, JSString username);
Future<void> registerWithFirebase(String email, String password, String username) async {
  await _registerWithFirebase(email.toJS, password.toJS, username.toJS).toDart;
}

@JS('logoutFromFirebase')
external JSPromise _logoutFromFirebase();
Future<void> logoutFromFirebase() async {
  await _logoutFromFirebase().toDart;
}

@JS('pickAndReadFile')
external void _pickAndReadFile(JSString inputId, JSFunction callback);

void pickAndReadFile(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  _pickAndReadFile(inputId.toJS, ((JSString base64, JSString fileName, JSString objectUrl) {
    callback(base64.toDart, fileName.toDart, objectUrl.toDart);
  }).toJS);
}

@JS('readInputFile')
external void _readInputFile(JSString inputId, JSFunction callback);

void readInputFile(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  _readInputFile(inputId.toJS, ((JSString base64, JSString fileName, JSString objectUrl) {
    callback(base64.toDart, fileName.toDart, objectUrl.toDart);
  }).toJS);
}

// DYNAMIC JS BINDING RESOLUTION
// Uses promiseToFuture and globalThis lookup to avoid compiler name mangling issues
Future<String> renderPublisherPage(String text) async {
  try {
    final promise = js_util.callMethod(js_util.globalThis, 'renderPublisherPage', [text]);
    final jsRes = await js_util.promiseToFuture(promise);
    return jsRes.toString();
  } catch (e) {
    print('[renderPublisherPage js_util Error] $e');
    rethrow;
  }
}

class WebFieldValue {
  static Map<String, dynamic> serverTimestamp() => {'__op': 'serverTimestamp'};
  static Map<String, dynamic> increment(num value) => {'__op': 'increment', 'value': value};
  static Map<String, dynamic> arrayUnion(List values) => {'__op': 'arrayUnion', 'values': values};
  static Map<String, dynamic> arrayRemove(List values) => {'__op': 'arrayRemove', 'values': values};
  static Map<String, dynamic> delete() => {'__op': 'delete'};
}