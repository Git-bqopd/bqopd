import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Ensures the user has a valid Firestore document with their UID as the key.
Future<void> ensureUserDocument() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final db = FirebaseFirestore.instance;
  final usersCollection = db.collection('Users');

  final uidDocRef = usersCollection.doc(user.uid);
  final uidDocSnap = await uidDocRef.get();

  if (uidDocSnap.exists) {
    await uidDocRef.update({'updatedAt': FieldValue.serverTimestamp()});
  } else {
    // Check for old email-based doc
    DocumentSnapshot? emailDocSnap;
    if (user.email != null) {
      emailDocSnap = await usersCollection.doc(user.email).get();
    }

    if (emailDocSnap != null && emailDocSnap.exists) {
      // Migration logic
      final oldData = emailDocSnap.data() as Map<String, dynamic>;
      await uidDocRef.set({
        ...oldData,
        'uid': user.uid,
        'email': user.email,
        'migratedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Create fresh real user
      await uidDocRef.set({
        'uid': user.uid,
        'email': user.email,
        'username': (user.email ?? '').split('@').first,
        'firstName': '',
        'lastName': '',
        'street1': '',
        'street2': '',
        'city': '',
        'state': '',
        'zipCode': '',
        'country': 'USA',
        'bio': '',
        'Editor': false,
        'newFanzine': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // Handle Registry for Real User
  final uname = ((user.displayName ?? '').trim().isNotEmpty)
      ? user.displayName!.trim()
      : (user.email ?? '').split('@').first;

  if (uname.isNotEmpty) {
    final unameDoc = db.collection('usernames').doc(uname.toLowerCase());
    final uSnap = await unameDoc.get();
    if (!uSnap.exists) {
      await unameDoc.set({
        'uid': user.uid,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}

/// Creates a "Managed" or "Estate" profile.
Future<String?> createManagedProfile({
  required String firstName,
  required String lastName,
  required String bio,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return null;

  final db = FirebaseFirestore.instance;

  // 1. Generate a new Random Document ID
  final newProfileRef = db.collection('Users').doc();

  // 2. Generate a URL-friendly username
  String baseHandle = '${firstName.trim()}-${lastName.trim()}'.toLowerCase();
  baseHandle = baseHandle.replaceAll(RegExp(r'[^a-z0-9-]'), '');

  if (baseHandle.length < 3) {
    baseHandle += '-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
  }

  // 3. Create the Document
  // Added 'Editor' and 'newFanzine' to match real user schema
  await newProfileRef.set({
    'uid': newProfileRef.id,
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    'username': baseHandle,
    'bio': bio,
    'isManaged': true,
    'managers': [currentUser.uid],
    'createdAt': FieldValue.serverTimestamp(),
    'email': '',
    'Editor': false, // Ensure consistency with real profiles
    'newFanzine': null, // Ensure consistency with real profiles
  });

  // 4. Register the Handle
  await db.collection('usernames').doc(baseHandle).set({
    'uid': newProfileRef.id,
    'isManaged': true,
    'createdAt': FieldValue.serverTimestamp(),
  });

  // 5. Add to Master Shortcodes
  await db.collection('shortcodes').doc(baseHandle.toUpperCase()).set({
    'type': 'user',
    'contentId': newProfileRef.id,
    'displayCode': baseHandle,
    'createdAt': FieldValue.serverTimestamp(),
  });

  return newProfileRef.id;
}