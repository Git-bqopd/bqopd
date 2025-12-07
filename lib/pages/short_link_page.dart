import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/fanzine_grid_view.dart';
import '../widgets/login_widget.dart';
import '../widgets/fanzine_widget.dart';
import '../widgets/profile_widget.dart';

class ShortLinkPage extends StatelessWidget {
  final String code;
  const ShortLinkPage({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    // Left Widget Logic:
    // If logged in -> Show "Home" / FanzineWidget (navigation hub)
    // If NOT logged in -> Show Login Widget (call to action)
    final leftWidget = FirebaseAuth.instance.currentUser == null
        ? LoginWidget(
      onTap: () => context.go('/register'),
    )
        : const FanzineWidget();

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

            // Result format: "type:ID" (e.g., "user:UID123" or "fanzine:ABC1234")
            final result = snap.data;

            if (result == null) {
              return const Center(child: Text('Page not found.'));
            }

            // CASE 1: It's a User Profile (e.g. /kevin)
            if (result.startsWith('user:')) {
              final userId = result.substring(5); // Remove 'user:' prefix
              return _PublicProfileView(userId: userId, leftWidget: leftWidget);
            }

            // CASE 2: It's a Fanzine (e.g. /QrnSbYA)
            if (result.startsWith('fanzine:')) {
              final fanzineCode = result.substring(8); // Remove 'fanzine:' prefix

              // For Fanzine View, we pass a specific FanzineWidget
              final specificFanzineWidget = FanzineWidget(
                fanzineShortCode: fanzineCode,
              );

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

    // --- 1. MASTER LOOKUP (shortcodes collection) ---
    // Try both UPPERCASE (fanzines) and lowercase (users)
    DocumentSnapshot masterDoc = await db.collection('shortcodes').doc(code.toUpperCase()).get();
    if (!masterDoc.exists) {
      masterDoc = await db.collection('shortcodes').doc(code.toLowerCase()).get();
    }

    if (masterDoc.exists) {
      final data = masterDoc.data() as Map<String, dynamic>;
      final type = data['type'];
      final contentId = data['contentId'];

      if (type == 'fanzine') {
        // Return the code needed for FanzineGridView
        return 'fanzine:${data['displayCode'] ?? code}';
      }
      else if (type == 'user') {
        // Return user UID
        return 'user:$contentId';
      }
    }

    // --- 2. FALLBACK LOOKUP ---

    // A) Check Fanzines collection directly
    final fz = await db
        .collection('fanzines')
        .where('shortCode', isEqualTo: code)
        .limit(1)
        .get();
    if (fz.docs.isNotEmpty) {
      return 'fanzine:$code';
    }

    // B) Check Usernames collection directly (doc ID is lowercase username)
    final unameDoc = await db.collection('usernames').doc(code.toLowerCase()).get();
    if (unameDoc.exists) {
      final data = unameDoc.data()!;
      final uid = data['uid'];
      if (uid != null) {
        return 'user:$uid';
      }
    }

    // C) Check Users collection directly (Last Resort)
    final usersByUsername = await db.collection('Users').where('username', isEqualTo: code).limit(1).get();
    if (usersByUsername.docs.isNotEmpty) {
      return 'user:${usersByUsername.docs.first.id}';
    }

    return null;
  }
}

class _PublicProfileView extends StatefulWidget {
  final String userId;
  final Widget leftWidget;
  const _PublicProfileView({required this.userId, required this.leftWidget});

  @override
  State<_PublicProfileView> createState() => _PublicProfileViewState();
}

class _PublicProfileViewState extends State<_PublicProfileView> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // This is the Public View layout
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Profile Widget (Read-Only Mode via targetUserId)
            AspectRatio(
              aspectRatio: 8 / 5,
              child: ProfileWidget(
                targetUserId: widget.userId, // Show THIS user's info
                currentIndex: _currentIndex,
                onFanzinesTapped: () => setState(() => _currentIndex = 0),
                onPagesTapped: () => setState(() => _currentIndex = 1),
              ),
            ),

            const SizedBox(height: 16),

            // 2. Public Content Grid
            _buildPublicContentGrid(widget.userId),

            const SizedBox(height: 32),

            // 3. Navigation/Login Widget at bottom
            widget.leftWidget,
          ],
        ),
      ),
    );
  }

  Widget _buildPublicContentGrid(String userId) {
    Query query;
    if (_currentIndex == 0) {
      // Fanzines
      query = FirebaseFirestore.instance
          .collection('fanzines')
          .where('editorId', isEqualTo: userId)
          .orderBy('creationDate', descending: true);
    } else {
      // Pages/Images
      query = FirebaseFirestore.instance
          .collection('images')
          .where('uploaderId', isEqualTo: userId)
          .orderBy('timestamp', descending: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const SizedBox(
            height: 100,
            child: Center(child: Text("No content found.")),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 5 / 8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;

            if (_currentIndex == 0) {
              // Fanzine Card
              final title = data['title'] ?? 'Untitled';
              return Container(
                decoration: BoxDecoration(
                  color: Colors.blueGrey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(8),
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              );
            } else {
              // Image Tile
              final url = data['fileUrl'] ?? '';
              if (url.isEmpty) return const SizedBox();
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(url, fit: BoxFit.cover),
              );
            }
          },
        );
      },
    );
  }
}