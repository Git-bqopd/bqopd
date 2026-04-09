import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'profile_page.dart';
import 'fanzine_reader_page.dart';

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
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('"$code" not found.', style: const TextStyle(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Go Back")),
                  ],
                ),
              );
            }

            // CASE 1: It's a User Profile (e.g. /kevin)
            if (result.startsWith('user:')) {
              final userId = result.substring(5);
              return ProfilePage(userId: userId);
            }

            // CASE 2: It's a Fanzine (e.g. /QrnSbYA)
            if (result.startsWith('fanzine:')) {
              final fanzineCode = result.substring(8);
              return FanzineReaderPage(shortCode: fanzineCode);
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
    final String cleanCode = code.trim();

    // 1. MASTER LOOKUP (Check shortcodes collection first for explicit mappings)
    // We check both UPPERCASE and lowercase to be safe
    final List<String> variations = [cleanCode.toUpperCase(), cleanCode.toLowerCase(), cleanCode];

    for (var v in variations) {
      DocumentSnapshot masterDoc = await db.collection('shortcodes').doc(v).get();
      if (masterDoc.exists) {
        final data = masterDoc.data() as Map<String, dynamic>;
        final type = data['type'];
        if (type == 'fanzine') return 'fanzine:${data['displayCode'] ?? cleanCode}';
        if (type == 'user') return 'user:${data['contentId']}';
      }
    }

    // 2. USERNAME REGISTRY LOOKUP (Check the usernames collection)
    final unameDoc = await db.collection('usernames').doc(cleanCode.toLowerCase()).get();
    if (unameDoc.exists) {
      final data = unameDoc.data() as Map<String, dynamic>;

      // Handle redirects/aliases (e.g., "The Comet" -> "kevin")
      if (data.containsKey('redirect')) {
        final targetHandle = data['redirect'] as String;
        final targetDoc = await db.collection('usernames').doc(targetHandle).get();
        if (targetDoc.exists) {
          final targetData = targetDoc.data() as Map<String, dynamic>;
          if (targetData['uid'] != null) return 'user:${targetData['uid']}';
        }
      }

      if (data['uid'] != null) return 'user:${data['uid']}';
    }

    // 3. FANZINE DIRECT LOOKUP (Search by shortCode field)
    final fz = await db.collection('fanzines')
        .where('shortCode', isEqualTo: cleanCode)
        .limit(1)
        .get();
    if (fz.docs.isNotEmpty) return 'fanzine:$cleanCode';

    // 4. USERS COLLECTION FALLBACK (Search by username field)
    final usersByUsername = await db.collection('Users')
        .where('username', isEqualTo: cleanCode.toLowerCase())
        .limit(1)
        .get();
    if (usersByUsername.docs.isNotEmpty) return 'user:${usersByUsername.docs.first.id}';

    return null;
  }
}