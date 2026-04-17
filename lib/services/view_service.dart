import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum ViewType { list, grid }

class ViewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Track an in-flight authentication request to prevent multiple sign-ins on load
  Future<User?>? _authInFlight;

  // Rule 1 Compliant Path
  CollectionReference get _viewLogsCollection => _db
      .collection('artifacts')
      .doc('bqopd')
      .collection('public')
      .doc('data')
      .collection('view_logs');

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

    // RULE 3 - Auth Before Queries
    User? user = _auth.currentUser;

    if (user == null) {
      try {
        // PREVENTION: If a sign-in is already happening, wait for it instead of starting a new one.
        if (_authInFlight == null) {
          debugPrint("ViewService: Initiating anonymous sign-in...");
          _authInFlight = _auth.signInAnonymously().then((cred) {
            final u = cred.user;
            debugPrint("ViewService: Anonymous sign-in successful: ${u?.uid}");
            return u;
          }).catchError((e) {
            _authInFlight = null; // Reset on failure to allow retry
            throw e;
          });
        }
        user = await _authInFlight;
      } catch (e) {
        debugPrint("Silent Auth Failed: $e");
        return;
      }
    }

    if (user == null) return;

    // CREATE A DETERMINISTIC ID:
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
        debugPrint("Successfully recorded unique view: $viewId");
      }
    } catch (e) {
      debugPrint("--- VIEW AGGREGATION ERROR ---");
      debugPrint("Operation: recordView (get/set)");
      debugPrint("Target Path: ${docRef.path}");
      debugPrint("User ID: ${user.uid} (Anonymous: ${user.isAnonymous})");
      debugPrint("Error Details: $e");
      debugPrint("Image ID Context: $imageId");
      debugPrint("------------------------------");
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