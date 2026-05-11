import 'package:cloud_firestore/cloud_firestore.dart';

/// Maps the serialized ISO string back into a real cloud_firestore Timestamp.
Map<String, dynamic> restoreTimestamps(Map<String, dynamic>? data) {
  if (data == null) return {};
  final res = <String, dynamic>{};
  data.forEach((k, v) {
    res[k] = _processValue(v);
  });
  return res;
}

dynamic _processValue(dynamic v) {
  if (v is Map) {
    if (v['__type'] == 'timestamp') {
      return Timestamp.fromDate(DateTime.parse(v['iso']));
    }
    return restoreTimestamps(Map<String, dynamic>.from(v));
  } else if (v is List) {
    return v.map((e) => _processValue(e)).toList();
  }
  return v;
}

/// A simulated DocumentSnapshot that strictly fulfills the interface requirements.
class WebDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  final String _path;
  final bool _exists;
  final Map<String, dynamic>? _data;

  WebDocumentSnapshot(this._path, this._exists, this._data);

  @override String get id => _path.split('/').last;
  @override Map<String, dynamic>? data() => _data;
  @override bool get exists => _exists;
  @override DocumentReference<Map<String, dynamic>> get reference => WebDocumentReference(_path);
  @override SnapshotMetadata get metadata => throw UnimplementedError();
  @override dynamic get(Object field) => _data?[field];
  @override dynamic operator [](Object field) => _data?[field];
}

class WebDocumentReference implements DocumentReference<Map<String, dynamic>> {
  final String _path;
  WebDocumentReference(this._path);

  @override String get id => _path.split('/').last;
  @override String get path => _path;
  @override CollectionReference<Map<String, dynamic>> get parent => throw UnimplementedError();
  @override FirebaseFirestore get firestore => throw UnimplementedError();

  @override Future<void> delete() => throw UnimplementedError();
  @override Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) => throw UnimplementedError();
  @override Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({bool includeMetadataChanges = false, ListenSource source = ListenSource.defaultSource}) => throw UnimplementedError();
  @override Future<void> set(Map<String, dynamic> data, [SetOptions? options]) => throw UnimplementedError();
  @override Future<void> update(Map<Object, Object?> data) => throw UnimplementedError();
  @override CollectionReference<Map<String, dynamic>> collection(String collectionPath) => throw UnimplementedError();
  @override DocumentReference<R> withConverter<R>({required FromFirestore<R> fromFirestore, required ToFirestore<R> toFirestore}) => throw UnimplementedError();
}