import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

String normalizeHandle(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');

Future<String?> claimHandle(String desiredRaw) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 'Not signed in';

  final handle = normalizeHandle(desiredRaw);
  if (handle.isEmpty) return 'Invalid handle';

  final db = FirebaseFirestore.instance;

  // 1. Check conflicts using UPPERCASE key
  // This ensures a user can't claim 'abc' if 'ABC' is already a shortcode
  final shortCodeKey = handle.toUpperCase();
  final short = await db.collection('shortcodes').doc(shortCodeKey).get();
  if (short.exists) return 'Handle is reserved';

  final ref = db.collection('usernames').doc(handle);
  final batch = db.batch();

  // 2. Create usernames/{handle}
  batch.set(ref, {
    'uid': user.uid,
    'createdAt': FieldValue.serverTimestamp(),
  });

  // 3. Mirror on the user's doc (using UID)
  final userDoc = db.collection('Users').doc(user.uid);
  batch.set(userDoc, {
    'uid': user.uid,
    'username': handle,
    'email': user.email,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // 4. Add to Master Lookup as UPPERCASE
  final shortcodeRef = db.collection('shortcodes').doc(shortCodeKey);
  batch.set(shortcodeRef, {
    'type': 'user',
    'contentId': user.uid,
    'createdAt': FieldValue.serverTimestamp(),
  });

  try {
    await batch.commit();
    return null;
  } on FirebaseException catch (e) {
    return e.message ?? 'Could not claim handle';
  }
}