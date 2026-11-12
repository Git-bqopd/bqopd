import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> ensureUserDocument() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return;
  }
  final db = FirebaseFirestore.instance;
  final userRef = db.collection('Users').doc(user.uid);
  final userSnap = await userRef.get();
  if (userSnap.exists) {
    await userRef.update({'updatedAt': FieldValue.serverTimestamp()});
  } else {
    await userRef.set({
      'uid': user.uid,
      'email': user.email,
      'role': 'user',
      'roles': [],
      'isCurator': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  final profileRef = db.collection('profiles').doc(user.uid);
  final profileSnap = await profileRef.get();
  if (!profileSnap.exists) {
    final defaultUsername = (user.email ?? '').split('@').first;
    await profileRef.set({
      'uid': user.uid,
      'username': defaultUsername,
      'displayName': user.displayName ?? '',
      'photoUrl': user.photoURL ?? '',
      'bio': '',
      'isManaged': false,
      'isCurator': false,
      'isAdmin': false,
      'managers': [],
      'followerCount': 0,
      'followingCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await db.collection('usernames').doc(defaultUsername.toLowerCase()).set({
      'uid': user.uid,
      'isManaged': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

Future<String?> createManagedProfile({
  String firstName = '',
  String lastName = '',
  String bio = '',
  String? displayName,
  String? explicitHandle,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    return null;
  }
  final db = FirebaseFirestore.instance;
  final profileRef = db.collection('profiles').doc();
  final resolvedDisplayName = (displayName != null && displayName.trim().isNotEmpty)
      ? displayName.trim()
      : "$firstName $lastName".trim();

  final String normalizedExplicit = (explicitHandle ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('@', '')
      .replaceAll(' ', '-')
      // ignore: deprecated_member_use
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');

  String baseHandle = normalizedExplicit.isNotEmpty
      ? normalizedExplicit
      // ignore: deprecated_member_use
      : resolvedDisplayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');
  if (baseHandle.isEmpty) {
    baseHandle = 'entity-${DateTime.now().millisecondsSinceEpoch}';
  }

  final profileData = {
    'uid': profileRef.id,
    'username': baseHandle,
    'displayName': resolvedDisplayName,
    if (firstName.trim().isNotEmpty) 'firstName': firstName.trim(),
    if (lastName.trim().isNotEmpty) 'lastName': lastName.trim(),
    'bio': bio,
    'photoUrl': '',
    'isManaged': true,
    'isCurator': false,
    'isAdmin': false,
    'managers': [currentUser.uid],
    'followerCount': 0,
    'followingCount': 0,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
  await profileRef.set(profileData);
  await db.collection('usernames').doc(baseHandle).set({
    'uid': profileRef.id,
    'isManaged': true,
    'createdAt': FieldValue.serverTimestamp(),
  });
  await db.collection('shortcodes').doc(baseHandle.toUpperCase()).set({
    'type': 'user',
    'contentId': profileRef.id,
    'displayCode': baseHandle,
    'createdAt': FieldValue.serverTimestamp(),
  });
  return profileRef.id;
}