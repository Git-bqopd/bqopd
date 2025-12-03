import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

// Standard: A-Z, 0-9 (Base36) - No lowercase allowed in the "Math"
const String _base36Chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

String _generateStandardCode() {
  final random = Random();
  String code = '';
  // 7 characters long
  for (int i = 0; i < 7; i++) {
    code += _base36Chars[random.nextInt(_base36Chars.length)];
  }
  return code;
}

String _generateVanityCode() {
  final random = Random();
  String randomPart = '';
  // 1. Generate 3 random alphanumeric chars
  for (int i = 0; i < 3; i++) {
    randomPart += _base36Chars[random.nextInt(_base36Chars.length)];
  }

  // 2. Insert "bqopd" (lowercase) at a random position (0 to 3)
  // This creates the "Display" version (e.g. "N7bqopd4")
  final insertPos = random.nextInt(4);
  return randomPart.substring(0, insertPos) +
      'bqopd' +
      randomPart.substring(insertPos);
}

Future<String?> assignShortcode(
    dynamic firestoreInstance, String contentType, String contentId,
    {bool isVanity = false}) async {

  final FirebaseFirestore db = firestoreInstance as FirebaseFirestore;

  String displayCode;  // e.g. "N7bqopd4" OR "7X91B2Z"
  String dbKey;        // e.g. "N7BQOPD4" OR "7X91B2Z" (The Search Key)

  bool isUnique = false;
  int retries = 0;
  const int maxRetries = 10;

  while (!isUnique && retries < maxRetries) {
    // 1. Generate based on preference
    if (isVanity) {
      displayCode = _generateVanityCode();
    } else {
      displayCode = _generateStandardCode();
    }

    // 2. Normalize for DB Lookup (Always Uppercase)
    dbKey = displayCode.toUpperCase();

    // 3. Check collisions in 'shortcodes' (Master Lookup)
    final docRef = db.collection('shortcodes').doc(dbKey);
    final docSnapshot = await docRef.get();

    // 4. Check collisions in 'usernames'
    // (Usernames are stored lowercase, so we check against lowercase version)
    final userRef = db.collection('usernames').doc(dbKey.toLowerCase());
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