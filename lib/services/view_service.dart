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
  /// Tracks "Registered Reader" count on the Image document for the social button.
  Future<void> recordView({
    required String imageId,
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
      } catch (_) {
        return;
      }
    }
    if (user == null) return;

    // Unique View Key: [User] + [Context] + [Type]
    // This ensures a user is only counted once for "Reading" this image in this specific zine.
    final String viewId = "${user.uid}_${fanzineId}_${type.name}";
    final docRef = _viewCollection(imageId).doc(viewId);

    try {
      final existingDoc = await docRef.get();

      if (!existingDoc.exists) {
        final batch = _db.batch();

        // 1. Record the detailed log under the IMAGE
        batch.set(docRef, {
          'userId': user.uid,
          'isAnonymous': user.isAnonymous,
          'fanzineId': fanzineId,
          'fanzineTitle': fanzineTitle,
          'viewType': type.name,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // 2. Update canonical counters on the IMAGE
        batch.update(_db.collection('images').doc(imageId), {
          'viewCount': FieldValue.increment(1),
          // "Registered Reader" = Logged In + Single Page
          if (!user.isAnonymous && type == ViewType.list)
            'registeredListViewCount': FieldValue.increment(1),
        });

        // 3. Update the FANZINE counter as a convenience cache for zine-level stats
        if (fanzineId.isNotEmpty && fanzineId != 'grid_view') {
          batch.update(_db.collection('fanzines').doc(fanzineId), {
            'totalEngagementViews': FieldValue.increment(1),
            if (!user.isAnonymous && type == ViewType.list)
              'registeredListViewCount': FieldValue.increment(1),
          });
        }

        await batch.commit();
      }
    } catch (e) {
      debugPrint("View record failed: $e");
    }
  }

  /// Returns logs for a specific image.
  Stream<QuerySnapshot> getViewLogsStream(String imageId) {
    return _viewCollection(imageId).snapshots();
  }

  /// Since we store logs under Images, to show a Fanzine's breakdown,
  /// we fetch the fanzine's own convenience logs if they exist,
  /// or summarize its cached counter.
  /// For now, we allow the FanzineWidget to use its own cached buckets.
  Stream<DocumentSnapshot> getFanzineStatsStream(String fanzineId) {
    return _db.collection('fanzines').doc(fanzineId).snapshots();
  }
}