import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/fanzine_grid_view.dart';
import '../widgets/login_widget.dart';
import '../widgets/fanzine_widget.dart'; // Import FanzineWidget

class ShortLinkPage extends StatelessWidget {
  final String code;
  const ShortLinkPage({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    // CHECK THIS LOGIC:
    // If logged in, we want to show the FanzineWidget (or ProfileWidget), NOT the placeholder.
    final leftWidget = FirebaseAuth.instance.currentUser == null
        ? const LoginWidget(onTap: null)
        : const FanzineWidget(); // CHANGED: Use FanzineWidget instead of _LoggedInPanel

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: FutureBuilder<String?>(
          future: _resolveShortcode(code),
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
              uiWidget: leftWidget, // Passing FanzineWidget here
            );
          },
        ),
      ),
    );
  }

  /// Resolves the incoming 'code' to a displayable fanzine shortcode.
  Future<String?> _resolveShortcode(String code) async {
    final db = FirebaseFirestore.instance;

    // --- 1. MASTER LOOKUP (The New Way) ---
    // Check the 'shortcodes' collection first. This is the fastest path.
    final masterDoc = await db.collection('shortcodes').doc(code).get();

    if (masterDoc.exists) {
      final data = masterDoc.data()!;
      final type = data['type'];
      final contentId = data['contentId'];

      if (type == 'fanzine') {
        // If it's a fanzine, return the code itself (since FanzineGridView expects a shortCode)
        // Note: Ensure 'code' matches what's stored as 'shortCode' in the fanzine doc.
        return code;
      }

      else if (type == 'user') {
        // If it's a user, contentId is the UID.
        // We need to look up that user to find their featured fanzine shortcode.
        final userDoc = await db.collection('Users').doc(contentId).get();

        if (userDoc.exists) {
          return userDoc.data()?['newFanzine'] as String?;
        }
      }
    }

    // --- 2. FALLBACK LEGACY LOOKUP (The Old Way) ---
    // If not found in 'shortcodes', maybe it's an old record?

    // A) Check Fanzines collection directly
    final fz = await db
        .collection('fanzines')
        .where('shortCode', isEqualTo: code)
        .limit(1)
        .get();
    if (fz.docs.isNotEmpty) return code;

    // B) Check Usernames collection directly
    final unameDoc = await db.collection('usernames').doc(code).get();
    if (!unameDoc.exists) return null;

    final data = unameDoc.data()!;
    final uid = (data['uid'] as String?)?.trim();
    final email = (data['email'] as String?)?.trim();

    DocumentSnapshot<Map<String, dynamic>>? userDoc;

    // Try a Users doc keyed by UID, then by email
    if (uid != null && uid.isNotEmpty) {
      userDoc = await db.collection('Users').doc(uid).get();
    }
    // If UID doc missing, try email (legacy schema)
    if ((userDoc == null || !userDoc.exists) && email != null && email.isNotEmpty) {
      userDoc = await db.collection('Users').doc(email).get();
    }

    if (userDoc == null || !userDoc.exists) return null;

    final userData = userDoc.data()!;
    return userData['newFanzine'] as String?;
  }
}

// You can remove _LoggedInPanel if it's no longer used, or keep it as a fallback.
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