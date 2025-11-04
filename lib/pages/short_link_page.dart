import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/fanzine_grid_view.dart';
import '../widgets/login_widget.dart';

class ShortLinkPage extends StatelessWidget {
  final String code;
  const ShortLinkPage({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final leftWidget = FirebaseAuth.instance.currentUser == null
        ? const LoginWidget(onTap: null)
        : const _LoggedInPanel(); // simple placeholder panel

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: FutureBuilder<String?>(
          future: _resolveToFanzineShortcode(code),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final resolvedShortCode = snap.data;
            if (resolvedShortCode == null) {
              return const Center(child: Text('Not found.'));
            }
            return FanzineGridView(
              shortCode: resolvedShortCode,
              uiWidget: leftWidget,
            );
          },
        ),
      ),
    );
  }

  /// Returns a fanzine shortcode to display, or null if nothing matches.
  Future<String?> _resolveToFanzineShortcode(String code) async {
    final db = FirebaseFirestore.instance;

    // 1) Direct fanzine shortcode?
    final fz = await db
        .collection('fanzines')
        .where('shortCode', isEqualTo: code)
        .limit(1)
        .get();
    if (fz.docs.isNotEmpty) return code;

    // 2) Username -> user (uid/email) -> user's newFanzine
    final unameDoc = await db.collection('usernames').doc(code).get();
    if (!unameDoc.exists) return null;

    final data = unameDoc.data()!;
    final uid = (data['uid'] as String?)?.trim();
    final email = (data['email'] as String?)?.trim();

    DocumentSnapshot<Map<String, dynamic>>? userDoc;

    // Try a Users doc keyed by UID (future-proof), then by email (your current schema)
    if (uid != null && uid.isNotEmpty) {
      userDoc = await db.collection('Users').doc(uid).get();
    }
    if ((userDoc == null || !userDoc.exists) && email != null && email.isNotEmpty) {
      userDoc = await db.collection('Users').doc(email).get();
    }
    if (userDoc == null || !userDoc.exists) return null;

    final userData = userDoc.data()!;
    return userData['newFanzine'] as String?;
  }
}

/// Very small placeholder for the left panel when logged in.
/// (Replace later with your real ProfileWidget if you want.)
class _LoggedInPanel extends StatelessWidget {
  const _LoggedInPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Container(
      color: const Color(0xFFF1B255),
      padding: const EdgeInsets.all(16),
      child: Text('profile: $email', style: const TextStyle(fontSize: 16)),
    );
  }
}
