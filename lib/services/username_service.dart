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

  final shortCodeKey = handle.toUpperCase();
  final short = await db.collection('shortcodes').doc(shortCodeKey).get();
  if (short.exists) return 'Handle is reserved';

  final ref = db.collection('usernames').doc(handle);

  try {
    await db.runTransaction((transaction) async {
      final docSnapshot = await transaction.get(ref);
      if (docSnapshot.exists) {
        throw Exception('Handle already taken');
      }

      transaction.set(ref, {
        'uid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final userDoc = db.collection('Users').doc(user.uid);
      transaction.set(userDoc, {
        'uid': user.uid,
        'username': handle,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final shortcodeRef = db.collection('shortcodes').doc(shortCodeKey);
      transaction.set(shortcodeRef, {
        'type': 'user',
        'contentId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    return null;
  } on FirebaseException catch (e) {
    return e.message ?? 'Could not claim handle';
  } catch (e) {
    return e.toString();
  }
}

/// Creates a redirection alias.
Future<String?> createAlias({
  required String aliasHandle,
  required String targetHandle,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 'Not signed in';

  final normalizedAlias = normalizeHandle(aliasHandle);
  final normalizedTarget = normalizeHandle(targetHandle);

  if (normalizedAlias.isEmpty || normalizedTarget.isEmpty) {
    return 'Invalid handles';
  }

  final db = FirebaseFirestore.instance;
  final aliasRef = db.collection('usernames').doc(normalizedAlias);
  final targetRef = db.collection('usernames').doc(normalizedTarget);

  try {
    await db.runTransaction((transaction) async {
      final aliasSnap = await transaction.get(aliasRef);
      if (aliasSnap.exists) {
        throw Exception('Alias handle "$normalizedAlias" is already taken.');
      }

      final targetSnap = await transaction.get(targetRef);
      if (!targetSnap.exists) {
        throw Exception('Target handle "$normalizedTarget" does not exist.');
      }

      transaction.set(aliasRef, {
        'redirect': normalizedTarget,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'isAlias': true,
      });
    });

    return null;
  } catch (e) {
    return e.toString();
  }
}