import 'dart:math';

const String _base62Chars =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

String generateShortcode() {
  final random = Random();
  String shortcode = '';
  for (int i = 0; i < 7; i++) {
    shortcode += _base62Chars[random.nextInt(_base62Chars.length)];
  }
  return shortcode;
}

// Note: FirebaseFirestore is not directly imported here.
// It's assumed that the calling code (e.g., in image_upload_modal.dart)
// will handle the Firestore instance and calls.
// This function provides the logic but expects a Firestore instance.
//
// To use this function, you would typically do something like:
//
// import 'package:cloud_firestore/cloud_firestore.dart';
// FirebaseFirestore firestore = FirebaseFirestore.instance;
// String? newShortcode = await assignShortcode(firestore, 'image', 'your_image_id');

Future<String?> assignShortcode(
    dynamic firestoreInstance, String contentType, String contentId) async {
  // It's better to type firestoreInstance as FirebaseFirestore
  // but to avoid direct dependency here, we use dynamic.
  // Ensure you pass a valid FirebaseFirestore instance.

  String shortcode;
  bool isUnique = false;
  int retries = 0;
  const int maxRetries = 10; // To prevent infinite loops in rare cases

  while (!isUnique && retries < maxRetries) {
    shortcode = generateShortcode();
    final docRef = firestoreInstance.collection('shortcodes').doc(shortcode);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      isUnique = true;
      try {
        await docRef.set({
          'type': contentType,
          'contentId': contentId,
          'createdAt': FieldValue.serverTimestamp(), // Uses Firestore server timestamp
        });
        return shortcode;
      } catch (e) {
        // Handle potential errors during Firestore write
        print('Error assigning shortcode: $e');
        return null;
      }
    }
    retries++;
  }
  if (retries >= maxRetries) {
    print('Failed to generate a unique shortcode after $maxRetries retries.');
  }
  return null; // Failed to find a unique shortcode
}
