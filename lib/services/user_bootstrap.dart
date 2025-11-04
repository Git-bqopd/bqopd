import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> ensureUserDocument() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.email == null) return;

  final users = FirebaseFirestore.instance.collection('Users');
  final docRef = users.doc(user.email);

  final snap = await docRef.get();
  if (snap.exists) {
    await docRef.update({'updatedAt': FieldValue.serverTimestamp()});
  } else {
    await docRef.set({
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

  // Keep a public handle registry for vanity URLs.
  final uname = ((user.displayName ?? '').trim().isNotEmpty)
      ? user.displayName!.trim()
      : (user.email ?? '').split('@').first;

  if (uname.isNotEmpty) {
    final unameDoc = FirebaseFirestore.instance
        .collection('usernames')
        .doc(uname.toLowerCase());
    await unameDoc.set({
      'uid': user.uid,
      'email': user.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
