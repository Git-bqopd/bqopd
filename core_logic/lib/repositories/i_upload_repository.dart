import 'dart:typed_data';

abstract class IUploadRepository {
  Future<String> uploadBytes(Uint8List bytes, String path, String contentType);
  Future<void> saveImageMetadata(Map<String, dynamic> data);
  Future<Map<String, dynamic>?> lookupUserByHandle(String handle);
}