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
  /// Tracks engagement buckets on the Image, the Fanzine, AND the specific Page.
  Future<void> recordView({
    required String imageId,
    required String? pageId, // Now required for per-page fanzine stats
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

    final String viewId = "${user.uid}_${fanzineId}_${type.name}";
    final docRef = _viewCollection(imageId).doc(viewId);

    try {
      final existingDoc = await docRef.get();

      if (!existingDoc.exists) {
        final batch = _db.batch();

        batch.set(docRef, {
          'userId': user.uid,
          'isAnonymous': user.isAnonymous,
          'fanzineId': fanzineId,
          'fanzineTitle': fanzineTitle,
          'viewType': type.name,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // 1. Update counters on the IMAGE (Global UGC Stats)
        batch.update(_db.collection('images').doc(imageId), {
          'viewCount': FieldValue.increment(1),
          if (!user.isAnonymous && type == ViewType.list)
            'registeredListViewCount': FieldValue.increment(1),
        });

        // 2. Update counters on the FANZINE (Publication Summary)
        if (fanzineId.isNotEmpty && fanzineId != 'grid_view') {
          batch.update(_db.collection('fanzines').doc(fanzineId), {
            'totalEngagementViews': FieldValue.increment(1),
            if (!user.isAnonymous && type == ViewType.list)
              'registeredListViewCount': FieldValue.increment(1),
          });

          // 3. Update counters on the specific PAGE (Detailed Breakdown)
          if (pageId != null && pageId.isNotEmpty) {
            final pageRef = _db.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId);

            // Determine which specific bucket to increment
            String field = '';
            if (user.isAnonymous) {
              field = (type == ViewType.list) ? 'anonListCount' : 'anonGridCount';
            } else {
              field = (type == ViewType.list) ? 'regListCount' : 'regGridCount';
            }

            batch.update(pageRef, {
              field: FieldValue.increment(1),
              'totalViews': FieldValue.increment(1),
            });
          }
        }

        await batch.commit();
      }
    } catch (e) {
      debugPrint("View record failed: $e");
    }
  }

  Stream<QuerySnapshot> getViewLogsStream(String imageId) {
    return _viewCollection(imageId).snapshots();
  }

  /// Streams all pages for a fanzine to build the detailed stats table.
  Stream<QuerySnapshot> getFanzinePagesStream(String fanzineId) {
    return _db.collection('fanzines').doc(fanzineId).collection('pages').orderBy('pageNumber').snapshots();
  }
}