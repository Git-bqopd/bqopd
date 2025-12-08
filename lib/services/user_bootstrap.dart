import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Ensures the user has a valid Firestore document with their UID as the key.
/// If an old "Email-key" document exists, it migrates the data to the UID location.
Future<void> ensureUserDocument() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final db = FirebaseFirestore.instance;
  final usersCollection = db.collection('Users');

  // 1. Check for the CORRECT (UID-based) document
  final uidDocRef = usersCollection.doc(user.uid);
  final uidDocSnap = await uidDocRef.get();

  if (uidDocSnap.exists) {
    // Perfect, they are already on the new system. Just update timestamp.
    await uidDocRef.update({'updatedAt': FieldValue.serverTimestamp()});
  } else {
    // 2. MIGRATION CHECK: Check if they have an old "Email-based" document
    DocumentSnapshot? emailDocSnap;
    if (user.email != null) {
      emailDocSnap = await usersCollection.doc(user.email).get();
    }

    if (emailDocSnap != null && emailDocSnap.exists) {
      // --- MIGRATION LOGIC ---
      print("Migrating user ${user.email} from Email ID to UID...");

      final oldData = emailDocSnap.data() as Map<String, dynamic>;

      // Copy data to new UID doc
      await uidDocRef.set({
        ...oldData,
        'uid': user.uid,
        'email': user.email,
        'migratedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print("Migration complete for ${user.uid}");

      // Optional: Delete old doc later
    } else {
      // 3. NEW USER (Fallback): Create fresh
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

  // --- Public Handle Registry ---
  final uname = ((user.displayName ?? '').trim().isNotEmpty)
      ? user.displayName!.trim()
      : (user.email ?? '').split('@').first;

  if (uname.isNotEmpty) {
    final unameDoc = db.collection('usernames').doc(uname.toLowerCase());
    final uSnap = await unameDoc.get();
    // Only set if not taken
    if (!uSnap.exists) {
      await unameDoc.set({
        'uid': user.uid,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}