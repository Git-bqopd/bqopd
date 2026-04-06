import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UploadRepository {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Uploads raw bytes to Firebase Storage and returns the download URL.
  Future<String> uploadBytes(Uint8List bytes, String path, String contentType) async {
    final ref = _storage.ref().child(path);
    final metadata = SettableMetadata(contentType: contentType);
    final uploadTask = await ref.putData(bytes, metadata);
    return await uploadTask.ref.getDownloadURL();
  }

  /// Creates a new image document in the global 'images' collection.
  Future<void> saveImageMetadata(Map<String, dynamic> data) async {
    final docRef = _db.collection('images').doc();
    await docRef.set({
      ...data,
      'internalRef': docRef.id,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Looks up a user's UID and display name by their @handle.
  Future<Map<String, dynamic>?> lookupUserByHandle(String handle) async {
    final cleanHandle = handle.toLowerCase().replaceAll('@', '');
    final query = await _db
        .collection('Users')
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