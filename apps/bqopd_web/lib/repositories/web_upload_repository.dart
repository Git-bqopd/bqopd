import 'dart:convert';
import 'dart:typed_data';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

class WebUploadRepository implements IUploadRepository {
  @override
  Future<String> uploadBytes(Uint8List bytes, String path, String contentType) async {
    return await stUpload(path, bytes, contentType);
  }

  @override
  Future<void> saveImageMetadata(Map<String, dynamic> data) async {
    final dataToSave = Map<String, dynamic>.from(data);
    dataToSave['timestamp'] = WebFieldValue.serverTimestamp();
    await fsAddDoc('images', jsonEncode(dataToSave));
  }

  @override
  Future<Map<String, dynamic>?> lookupUserByHandle(String handle) async {
    final cleanHandle = handle.toLowerCase().replaceAll('@', '');
    final resStr = await fsQuery('profiles', 'username', '==', jsonEncode(cleanHandle), '');
    final List docs = jsonDecode(resStr);

    if (docs.isNotEmpty) {
      final doc = docs.first;
      final data = doc['data'];
      return {
        'uid': doc['id'],
        'name': data['displayName'] ?? data['username'] ?? handle,
      };
    }
    return null;
  }
}