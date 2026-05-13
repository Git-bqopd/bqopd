/// Maps the serialized ISO string back into a pure Dart DateTime object.
/// This completely eliminates the need for cloud_firestore's Timestamp class in the Jaspr Web app.
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
    // Intercept our custom JS interop timestamp format
    if (v['__type'] == 'timestamp') {
      return DateTime.parse(v['iso']);
    }
    // Recursively process nested maps
    return restoreTimestamps(Map<String, dynamic>.from(v));
  } else if (v is List) {
    // Recursively process arrays
    return v.map((e) => _processValue(e)).toList();
  }
  return v;
}