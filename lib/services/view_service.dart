import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum ViewType { list, grid }

class ViewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Use a standard root collection since you are using your own Firebase project (bqopd-9ce06).
  // The 'artifacts/...' path is only needed for the AI platform's shared sandbox database.
  CollectionReference get _viewLogsCollection => _db.collection('view_logs');

  /// Records a view for canonical content (Image).
  Future<void> recordView({
    required String imageId,
    required String? pageId,
    required String fanzineId,
    required String fanzineTitle,
    required ViewType type,
  }) async {
    if (imageId.isEmpty) return;

    // Rule 3: Auth Before Queries
    User? user = _auth.currentUser;
    if (user == null) {
      try {
        final cred = await _auth.signInAnonymously();
        user = cred.user;
      } catch (_) { return; }
    }

    if (user == null) return;

    // Unique ID: user_image_mode to prevent spam
    final String viewId = "${user.uid}_${imageId}_${type.name}";
    final docRef = _viewLogsCollection.doc(viewId);

    try {
      final existingDoc = await docRef.get();

      if (!existingDoc.exists) {
        final batch = _db.batch();

        batch.set(docRef, {
          'imageId': imageId,
          'userId': user.uid,
          'isAnonymous': user.isAnonymous,
          'fanzineId': fanzineId,
          'fanzineTitle': fanzineTitle,
          'viewType': type.name,
          'timestamp': FieldValue.serverTimestamp(),
        });

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
        debugPrint("View recorded: $imageId");
      }
    } catch (e) {
      debugPrint("View record failed: $e");
    }
  }

  Stream<QuerySnapshot> getViewLogsStream(String imageId) {
    // RULE 2: No complex queries. Simple collection stream.
    return _viewLogsCollection.snapshots();
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