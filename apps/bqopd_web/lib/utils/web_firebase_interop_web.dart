import 'dart:js_interop';
import 'dart:typed_data';

@JS('window.getCurrentUserId')
external JSString? _getCurrentUserId();
String? getCurrentUserId() => _getCurrentUserId()?.toDart;

@JS('window.fsGetDoc')
external JSPromise _fsGetDoc(JSString path);
Future<String> fsGetDoc(String path) async {
  final jsRes = await _fsGetDoc(path.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('window.fsListenDoc')
external JSFunction _fsListenDoc(JSString path, JSFunction callback);
dynamic fsListenDoc(String path, void Function(String) callback) {
  return _fsListenDoc(path.toJS, ((JSString str) => callback(str.toDart)).toJS);
}

@JS('window.fsListenQuery')
external JSFunction _fsListenQuery(JSString path, JSString field, JSString op, JSString valueJson, JSString orderBy, JSBoolean desc, JSFunction callback);
dynamic fsListenQuery(String path, String field, String op, String valueJson, String orderBy, bool desc, void Function(String) callback) {
  return _fsListenQuery(path.toJS, field.toJS, op.toJS, valueJson.toJS, orderBy.toJS, desc.toJS, ((JSString str) => callback(str.toDart)).toJS);
}

@JS('window.fsUpdateDoc')
external JSPromise _fsUpdateDoc(JSString path, JSString dataJson);
Future<void> fsUpdateDoc(String path, String dataJson) async {
  await _fsUpdateDoc(path.toJS, dataJson.toJS).toDart;
}

@JS('window.fsSetDoc')
external JSPromise _fsSetDoc(JSString path, JSString dataJson, JSBoolean merge);
Future<void> fsSetDoc(String path, String dataJson, bool merge) async {
  await _fsSetDoc(path.toJS, dataJson.toJS, merge.toJS).toDart;
}

@JS('window.fsDeleteDoc')
external JSPromise _fsDeleteDoc(JSString path);
Future<void> fsDeleteDoc(String path) async {
  await _fsDeleteDoc(path.toJS).toDart;
}

@JS('window.fsAddDoc')
external JSPromise _fsAddDoc(JSString path, JSString dataJson);
Future<String> fsAddDoc(String path, String dataJson) async {
  final jsRes = await _fsAddDoc(path.toJS, dataJson.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('window.fsQuery')
external JSPromise _fsQuery(JSString path, JSString field, JSString op, JSString valueJson, JSString orderBy);
Future<String> fsQuery(String path, String field, String op, String valueJson, String orderBy) async {
  final jsRes = await _fsQuery(path.toJS, field.toJS, op.toJS, valueJson.toJS, orderBy.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('window.fnCall')
external JSPromise _fnCall(JSString name, JSString dataJson);
Future<String> fnCall(String name, String dataJson) async {
  final jsRes = await _fnCall(name.toJS, dataJson.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('window.stUpload')
external JSPromise _stUpload(JSString path, JSUint8Array bytes, JSString contentType);
Future<String> stUpload(String path, Uint8List bytes, String contentType) async {
  final jsRes = await _stUpload(path.toJS, bytes.toJS, contentType.toJS).toDart;
  return (jsRes as JSString).toDart;
}

class WebFieldValue {
  static Map<String, dynamic> serverTimestamp() => {'__op': 'serverTimestamp'};
  static Map<String, dynamic> increment(num value) => {'__op': 'increment', 'value': value};
  static Map<String, dynamic> arrayUnion(List values) => {'__op': 'arrayUnion', 'values': values};
  static Map<String, dynamic> arrayRemove(List values) => {'__op': 'arrayRemove', 'values': values};
  static Map<String, dynamic> delete() => {'__op': 'delete'};
}