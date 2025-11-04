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

  // Optional: prevent conflicts with existing shortcodes
  final short = await db.collection('shortcodes').doc(handle).get();
  if (short.exists) return 'Handle is reserved';

  final ref = db.collection('usernames').doc(handle);
  final batch = db.batch();

  // Try to create usernames/{handle} with your uid
  batch.set(ref, {
    'uid': user.uid,
    'createdAt': FieldValue.serverTimestamp(),
  });

  // Also mirror on the user's doc (by email for your current app)
  final userDoc = db.collection('Users').doc(user.email);
  batch.set(userDoc, {
    'uid': user.uid,
    'username': handle,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  try {
    await batch.commit(); // will fail if rule denies because handle exists
    return null; // success
  } on FirebaseException catch (e) {
    return e.message ?? 'Could not claim handle';
  }
}
