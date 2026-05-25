import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Flutter service responsible for generating, verifying, and assigning unique shortcodes.
/// Uses the unified pure-Dart ShortcodeGenerator from our core package.
class ShortcodeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Generates a unique shortcode and registers it in the database.
  Future<String?> assignShortcode({
    required String contentType,
    required String contentId,
    bool isVanity = false,
  }) async {
    String displayCode;
    String dbKey;

    bool isUnique = false;
    int retries = 0;
    const int maxRetries = 10;

    while (!isUnique && retries < maxRetries) {
      // Use our unified generator from core
      if (isVanity) {
        displayCode = ShortcodeGenerator.generateVanityCode();
      } else {
        displayCode = ShortcodeGenerator.generateStandardCode();
      }

      dbKey = displayCode.toUpperCase();

      // Check collisions in 'shortcodes' (Master Lookup)
      final docRef = _db.collection('shortcodes').doc(dbKey);
      final docSnapshot = await docRef.get();

      // Check collisions in 'usernames'
      final userRef = _db.collection('usernames').doc(dbKey.toLowerCase());
      final userSnapshot = await userRef.get();

      if (!docSnapshot.exists && !userSnapshot.exists) {
        isUnique = true;
        try {
          // Store in Master Lookup using the UPPERCASE key
          await docRef.set({
            'type': contentType,
            'contentId': contentId,
            'displayCode': displayCode, // Store how it should look visually
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Return the DISPLAY version to the UI
          return displayCode;
        } catch (e) {
          print('Error assigning shortcode: $e');
          rethrow;
        }
      }
      retries++;
    }

    if (retries >= maxRetries) {
      throw Exception('Failed to generate a unique shortcode after $maxRetries retries.');
    }
    return null;
  }
}