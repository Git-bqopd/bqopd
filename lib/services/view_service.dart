import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum ViewType { list, grid }

class ViewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _viewLogsCollection => _db.collection('view_logs');

  /// Records a unique view for canonical content (Image).
  /// Prevents double-counting by using a document ID format: {userId}_{imageId}_{viewType}
  Future<void> recordView({
    required String imageId,
    required String? pageId,
    required String fanzineId,
    required String fanzineTitle,
    required ViewType type,
  }) async {
    if (imageId.isEmpty) return;

    // RULE: Do not trigger a new sign-in if we already have a user (Anonymous or Real)
    User? user = _auth.currentUser;

    if (user == null) {
      try {
        // Attempt to sign in anonymously ONLY if no session exists
        final cred = await _auth.signInAnonymously();
        user = cred.user;
      } catch (e) {
        debugPrint("Silent Auth Failed: $e");
        return;
      }
    }

    if (user == null) return;

    // CREATE A DETERMINISTIC ID:
    // This ensures if the same user (session) views the same image,
    // the set() operation just overwrites rather than creating a new log or incrementing.
    final String viewId = "${user.uid}_${imageId}_${type.name}";
    final docRef = _viewLogsCollection.doc(viewId);

    try {
      // Check if this specific user has ALREADY viewed this specific image/mode combo
      final existingDoc = await docRef.get();

      if (!existingDoc.exists) {
        final batch = _db.batch();

        // 1. Log the unique view
        batch.set(docRef, {
          'imageId': imageId,
          'userId': user.uid,
          'isAnonymous': user.isAnonymous,
          'fanzineId': fanzineId,
          'fanzineTitle': fanzineTitle,
          'viewType': type.name,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // 2. Increment the bucket on the master image document
        String bucketField = "";
        if (user.isAnonymous) {
          bucketField = (type == ViewType.list) ? 'anonListCount' : 'anonGridCount';
        } else {
          bucketField = (type == ViewType.list) ? 'regListCount' : 'regGridCount';
        }

        batch.update(_db.collection('images').doc(imageId), {
          bucketField: FieldValue.increment(1),
        });

        await batch.commit();
        debugPrint("Unique view recorded for image: $imageId");
      }
    } catch (e) {
      debugPrint("View aggregation failed: $e");
    }
  }

  Stream<QuerySnapshot> getFanzinePagesStream(String fanzineId) {
    return _db
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber')
        .snapshots();
  }
}