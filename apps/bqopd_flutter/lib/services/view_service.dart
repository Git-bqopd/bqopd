import 'package:bqopd_core/bqopd_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Concrete implementation of the [IViewService] interface for Flutter.
/// Aggregates and records unique and anonymous viewer impressions.
class ViewService implements IViewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Future<User?>? _authInFlight;

  CollectionReference get _viewLogsCollection => _db
      .collection('artifacts')
      .doc('bqopd')
      .collection('public')
      .doc('data')
      .collection('view_logs');

  @override
  Future<void> recordView({
    required String imageId,
    required String? pageId,
    required String fanzineId,
    required String fanzineTitle,
    required ViewType type,
  }) async {
    if (imageId.isEmpty) {
      return;
    }

    User? user = _auth.currentUser;
    if (user == null) {
      try {
        if (_authInFlight == null) {
          debugPrint("ViewService: Initiating anonymous sign-in...");
          _authInFlight = _auth.signInAnonymously().then((cred) {
            final u = cred.user;
            debugPrint("ViewService: Anonymous sign-in successful: ${u?.uid}");
            return u;
          }).catchError((e) {
            _authInFlight = null;
            throw e;
          });
        }
        user = await _authInFlight;
      } catch (e) {
        debugPrint("Silent Auth Failed: $e");
        return;
      }
    }

    if (user == null) {
      return;
    }

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
          bucketField =
          (type == ViewType.list) ? 'anonListCount' : 'anonGridCount';
        } else {
          bucketField =
          (type == ViewType.list) ? 'regListCount' : 'regGridCount';
        }

        batch.update(_db.collection('images').doc(imageId), {
          bucketField: FieldValue.increment(1),
        });

        await batch.commit();
        debugPrint("Successfully recorded unique view: $viewId");
      }
    } catch (e) {
      debugPrint("--- VIEW AGGREGATION ERROR ---");
      debugPrint("Error Details: $e");
    }
  }

  @override
  Stream<QuerySnapshot> getFanzinePagesStream(String fanzineId) {
    return _db
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber')
        .snapshots();
  }
}