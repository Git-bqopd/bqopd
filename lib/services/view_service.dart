import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class ViewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Records a view for a piece of content.
  ///
  /// [contentId] is the MASTER ID of the content (e.g. image ID).
  /// This ensures views are counted towards the creator's original upload,
  /// regardless of which Fanzine it appears in.
  Future<void> recordView({
    required String contentId,
    required String contentType, // e.g., 'images', 'fanzines'
  }) async {
    User? user = _auth.currentUser;
    // 1. Ensure User ID (Anonymous or Real)
    if (user == null) {
      try {
        final cred = await _auth.signInAnonymously();
        user = cred.user;
      } catch (e) {
        // debugPrint("Error signing in anonymously for view tracking: $e");
        return;
      }
    }

    if (user == null) return;

    // 2. Log to Google Analytics
    try {
      await _analytics.logEvent(
        name: 'select_content',
        parameters: {
          'content_type': contentType,
          'content_id': contentId,
          'user_id': user.uid,
        },
      );
    } catch (e) {
      // Analytics failures are non-critical
    }

    // 3. Record Unique View in Firestore
    final docRef = _db
        .collection('stats')
        .doc('views')
        .collection(contentType)
        .doc(contentId)
        .collection('unique_viewers')
        .doc(user.uid);

    try {
      // Idempotent write
      await docRef.set({
        'viewedAt': FieldValue.serverTimestamp(),
        'uid': user.uid,
        'isAnonymous': user.isAnonymous,
      }, SetOptions(merge: true));
    } catch (e) {
      // Suppress permission errors specifically to keep console clean during dev
      if (e.toString().contains('permission-denied')) {
        // Commented out to silence the specific log as requested
        debugPrint(
            "Note: View tracking skipped (Permission Denied). Enable writes to 'stats' collection in Firestore Rules.");
      } else {
        debugPrint("Error recording view to Firestore: $e");
      }
    }
  }

  /// Returns the live count of unique viewers.
  Future<int> getViewCount({
    required String contentId,
    required String contentType,
  }) async {
    try {
      final query = _db
          .collection('stats')
          .doc('views')
          .collection(contentType)
          .doc(contentId)
          .collection('unique_viewers')
          .count();

      final snapshot = await query.get(source: AggregateSource.server);
      return snapshot.count ?? 0;
    } catch (e) {
      if (!e.toString().contains('permission-denied')) {
        debugPrint("Error fetching view count: $e");
      }
      return 0;
    }
  }
}
