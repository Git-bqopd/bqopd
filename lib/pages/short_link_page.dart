import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/fanzine_grid_view.dart';
import '../widgets/fanzine_widget.dart';
import 'profile_page.dart'; // Import the Unified Profile Page

class ShortLinkPage extends StatelessWidget {
  final String code;
  const ShortLinkPage({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
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

            final result = snap.data;
            if (result == null) {
              return const Center(child: Text('Page not found.'));
            }

            // CASE 1: It's a User Profile (e.g. /kevin)
            if (result.startsWith('user:')) {
              final userId = result.substring(5);
              // ROUTING TO THE UNIFIED PROFILE PAGE
              return ProfilePage(userId: userId);
            }

            // CASE 2: It's a Fanzine (e.g. /QrnSbYA)
            if (result.startsWith('fanzine:')) {
              final fanzineCode = result.substring(8);
              final specificFanzineWidget = FanzineWidget(fanzineShortCode: fanzineCode);
              return FanzineGridView(
                shortCode: fanzineCode,
                uiWidget: specificFanzineWidget,
              );
            }

            return const Center(child: Text('Unknown content type.'));
          },
        ),
      ),
    );
  }

  /// Resolves the incoming URL code to a specific Type and ID.
  Future<String?> _resolveShortcode(String code) async {
    final db = FirebaseFirestore.instance;

    // 1. MASTER LOOKUP
    DocumentSnapshot masterDoc = await db.collection('shortcodes').doc(code.toUpperCase()).get();
    if (!masterDoc.exists) {
      masterDoc = await db.collection('shortcodes').doc(code.toLowerCase()).get();
    }

    if (masterDoc.exists) {
      final data = masterDoc.data() as Map<String, dynamic>;
      final type = data['type'];
      if (type == 'fanzine') return 'fanzine:${data['displayCode'] ?? code}';
      if (type == 'user') return 'user:${data['contentId']}';
    }

    // 2. FALLBACK LOOKUPS
    final fz = await db.collection('fanzines').where('shortCode', isEqualTo: code).limit(1).get();
    if (fz.docs.isNotEmpty) return 'fanzine:$code';

    final unameDoc = await db.collection('usernames').doc(code.toLowerCase()).get();
    if (unameDoc.exists && unameDoc.data()!['uid'] != null) return 'user:${unameDoc.data()!['uid']}';

    final usersByUsername = await db.collection('Users').where('username', isEqualTo: code).limit(1).get();
    if (usersByUsername.docs.isNotEmpty) return 'user:${usersByUsername.docs.first.id}';

    return null;
  }
}