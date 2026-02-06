import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum ViewType { list, grid }

class ViewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Rule 1 Compliant Path: Logs are stored per Image (the UGC)
  CollectionReference _viewCollection(String imageId) {
    return _db
        .collection('artifacts')
        .doc('bqopd')
        .collection('public')
        .doc('data')
        .collection('views')
        .doc(imageId)
        .collection('logs');
  }

  /// Records a view for canonical content (Image).
  /// Tracks engagement in 4 distinct buckets on the Image document.
  Future<void> recordView({
    required String imageId,
    required String? pageId,
    required String fanzineId,
    required String fanzineTitle,
    required ViewType type,
  }) async {
    if (imageId.isEmpty) return;

    User? user = _auth.currentUser;
    if (user == null) {
      try {
        final cred = await _auth.signInAnonymously();
        user = cred.user;
      } catch (_) { return; }
    }
    if (user == null) return;

    // Unique ID for this specific action (e.g., "uid_zine_list")
    // This ensures we only count a specific user/zine/mode combo ONCE.
    final String viewId = "${user.uid}_${fanzineId}_${type.name}";
    final docRef = _viewCollection(imageId).doc(viewId);

    try {
      final existingDoc = await docRef.get();

      if (!existingDoc.exists) {
        final batch = _db.batch();

        // 1. Create Ledger Entry (Context & History)
        batch.set(docRef, {
          'userId': user.uid,
          'isAnonymous': user.isAnonymous,
          'fanzineId': fanzineId,
          'fanzineTitle': fanzineTitle,
          'viewType': type.name,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // 2. Determine which of the 4 buckets to increment
        String bucketField = "";
        if (user.isAnonymous) {
          bucketField = (type == ViewType.list) ? 'anonListCount' : 'anonGridCount';
        } else {
          bucketField = (type == ViewType.list) ? 'regListCount' : 'regGridCount';
        }

        // 3. Update Image Document with specific bucket increment ONLY
        batch.update(_db.collection('images').doc(imageId), {
          bucketField: FieldValue.increment(1),
        });

        await batch.commit();
      }
    } catch (e) {
      debugPrint("View record failed: $e");
    }
  }

  Stream<QuerySnapshot> getViewLogsStream(String imageId) {
    return _viewCollection(imageId).snapshots();
  }

  Stream<QuerySnapshot> getFanzinePagesStream(String fanzineId) {
    return _db.collection('fanzines').doc(fanzineId).collection('pages').orderBy('pageNumber').snapshots();
  }
}