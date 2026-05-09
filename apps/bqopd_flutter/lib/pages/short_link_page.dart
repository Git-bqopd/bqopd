import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'profile_page.dart';
import 'fanzine_reader_page.dart';

class ShortLinkPage extends StatefulWidget {
  final String code;
  const ShortLinkPage({super.key, required this.code});

  @override
  State<ShortLinkPage> createState() => _ShortLinkPageState();
}

class _ShortLinkPageState extends State<ShortLinkPage> {
  late Future<String?> _resolveFuture;

  @override
  void initState() {
    super.initState();
    // Cache the resolution future to prevent "amnesia" when popping
    // back to this page from an editor or modal.
    _resolveFuture = _resolveShortcode(widget.code);
  }

  @override
  void didUpdateWidget(covariant ShortLinkPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      setState(() {
        _resolveFuture = _resolveShortcode(widget.code);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: FutureBuilder<String?>(
          future: _resolveFuture,
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
                    Text('"${widget.code}" not found.', style: const TextStyle(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Go Back")),
                  ],
                ),
              );
            }

            if (result.startsWith('user:')) {
              final userId = result.substring(5);
              return ProfilePage(userId: userId);
            }

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

  Future<String?> _resolveShortcode(String code) async {
    final db = FirebaseFirestore.instance;
    final String cleanCode = code.trim();

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

    final unameDoc = await db.collection('usernames').doc(cleanCode.toLowerCase()).get();
    if (unameDoc.exists) {
      final data = unameDoc.data() as Map<String, dynamic>;
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

    final fz = await db.collection('fanzines')
        .where('shortCode', isEqualTo: cleanCode)
        .limit(1)
        .get();
    if (fz.docs.isNotEmpty) return 'fanzine:$cleanCode';

    // Fallback check redirected to 'profiles'
    final profilesByUsername = await db.collection('profiles')
        .where('username', isEqualTo: cleanCode.toLowerCase())
        .limit(1)
        .get();
    if (profilesByUsername.docs.isNotEmpty) return 'user:${profilesByUsername.docs.first.id}';

    return null;
  }
}