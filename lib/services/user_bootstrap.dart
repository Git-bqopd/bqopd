import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Ensures the user has a valid Firestore setup.
/// Real users get a record in 'Users' (private/system) and 'profiles' (public).
Future<void> ensureUserDocument() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final db = FirebaseFirestore.instance;

  // 1. Private User Record (System/Auth Data)
  final userRef = db.collection('Users').doc(user.uid);
  final userSnap = await userRef.get();

  if (userSnap.exists) {
    await userRef.update({'updatedAt': FieldValue.serverTimestamp()});
  } else {
    await userRef.set({
      'uid': user.uid,
      'email': user.email,
      'role': 'user', // Default role
      'roles': [],    // NEW: roles list
      'isCurator': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 2. Public Profile Record (Unified Display Data)
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
      'isCurator': false, // Public flag
      'isAdmin': false,   // NEW: Public flag
      'managers': [],
      'followerCount': 0,
      'followingCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Register handle in global registry
    await db.collection('usernames').doc(defaultUsername.toLowerCase()).set({
      'uid': user.uid,
      'isManaged': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Creates a "Managed" profile (Estate/Historical Entity).
/// These exist ONLY in the 'profiles' collection and are controlled by real users.
Future<String?> createManagedProfile({
  required String firstName,
  required String lastName,
  required String bio,
  String? explicitHandle,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return null;

  final db = FirebaseFirestore.instance;
  final profileRef = db.collection('profiles').doc();

  final fullName = "$firstName $lastName".trim();

  // Use the explicit handle if provided, otherwise fallback to the old generation logic
  String baseHandle = explicitHandle ?? fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');

  if (baseHandle.isEmpty) {
    baseHandle = 'entity-${DateTime.now().millisecondsSinceEpoch}';
  }

  final profileData = {
    'uid': profileRef.id,
    'username': baseHandle,
    'displayName': fullName,
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
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

  // Register handle
  await db.collection('usernames').doc(baseHandle).set({
    'uid': profileRef.id,
    'isManaged': true,
    'createdAt': FieldValue.serverTimestamp(),
  });

  // Add to Master Shortcodes for /handle navigation
  await db.collection('shortcodes').doc(baseHandle.toUpperCase()).set({
    'type': 'user',
    'contentId': profileRef.id,
    'displayCode': baseHandle,
    'createdAt': FieldValue.serverTimestamp(),
  });

  return profileRef.id;
}