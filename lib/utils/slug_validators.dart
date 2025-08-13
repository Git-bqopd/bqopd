import 'package:cloud_firestore/cloud_firestore.dart';

final RegExp shortcodeRegExp = RegExp(r'^[0-9A-HJKMNP-TV-Z]{7}$');
final RegExp aliasRegExp = RegExp(r'^[A-Za-z0-9-]{3,39}$');
const Set<String> reserved = {
  'admin',
  'login',
  'auth',
  'api',
  'about',
  'terms',
  'privacy',
};

Future<void> claimUsername(FirebaseFirestore db, String username) async {
  final lower = username.toLowerCase();
  if (shortcodeRegExp.hasMatch(username)) {
    throw Exception('Username cannot be a shortcode');
  }
  if (!aliasRegExp.hasMatch(username)) {
    throw Exception('Invalid username');
  }
  if (reserved.contains(lower)) {
    throw Exception('Reserved username');
  }
  final ref = db.doc('aliases/$lower');
  final snap = await ref.get();
  if (snap.exists) {
    throw Exception('Alias already exists');
  }
  await ref.set({'createdAt': FieldValue.serverTimestamp()});
}
