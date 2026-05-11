import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Concrete Firebase implementation of the IUploadRepository interface.
class FirebaseUploadRepository implements IUploadRepository {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Future<String> uploadBytes(Uint8List bytes, String path, String contentType) async {
    final ref = _storage.ref().child(path);
    final metadata = SettableMetadata(contentType: contentType);
    final uploadTask = await ref.putData(bytes, metadata);
    return await uploadTask.ref.getDownloadURL();
  }

  @override
  Future<void> saveImageMetadata(Map<String, dynamic> data) async {
    final docRef = _db.collection('images').doc();
    await docRef.set({
      ...data,
      'internalRef': docRef.id,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<Map<String, dynamic>?> lookupUserByHandle(String handle) async {
    final cleanHandle = handle.toLowerCase().replaceAll('@', '');
    final query = await _db
        .collection('profiles')
        .where('username', isEqualTo: cleanHandle)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final data = doc.data();
      return {
        'uid': doc.id,
        'name': data['displayName'] ?? data['username'] ?? handle,
      };
    }
    return null;
  }
}