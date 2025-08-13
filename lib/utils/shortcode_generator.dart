import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

const String _crockford32Chars =
    '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String generateShortcode() {
  final random = Random();
  final StringBuffer shortcode = StringBuffer();
  for (int i = 0; i < 7; i++) {
    shortcode.write(
        _crockford32Chars[random.nextInt(_crockford32Chars.length)]);
  }
  return shortcode.toString();
}

Future<void> reserveShortcode(FirebaseFirestore firestore, String code,
    Map<String, dynamic> data) async {
  final ref = firestore.doc('codes/$code');
  await firestore.runTransaction((tx) async {
    final snap = await tx.get(ref);
    if (snap.exists) {
      throw Exception('Shortcode already exists');
    }
    tx.set(ref, data);
  });
}

Future<String?> assignShortcode(
    FirebaseFirestore firestore, String type, String targetRef) async {
  for (int i = 0; i < 10; i++) {
    final code = generateShortcode();
    try {
      await reserveShortcode(firestore, code, {
        'type': type,
        'targetRef': targetRef,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return code;
    } catch (_) {
      continue;
    }
  }
  return null;
}
