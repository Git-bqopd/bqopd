import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/user_provider.dart';
import '../widgets/profile_widget.dart';
import '../widgets/new_fanzine_modal.dart';
import '../widgets/image_view_modal.dart';
import '../widgets/login_widget.dart';
import '../widgets/fanzine_widget.dart';
// Note: We don't need imports for Pages that we navigate to via named routes,
// but we keep them if we use classes for other reasons.
// However, to fix navigation we replace Navigator.push calls.

class ProfilePage extends StatefulWidget {
  final String? userId; // Optional: If null, uses current user
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // 0 = Editor, 1 = Fanzines, 2 = Pages
  int _currentIndex = 1;
  bool _hasDefaultedTab = false; // Track if we've auto-switched tab for owner

  void _showNewFanzineModal(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewFanzineModal(userId: userId),
    );
  }

  // UPDATED: Removed circular border radius
  ButtonStyle get _blueButtonStyle => TextButton.styleFrom(
    backgroundColor: Colors.blueAccent,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
  );

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUid = userProvider.currentUserId;

    // Determine Target User (Dynamic based on provider)
    // If widget.userId is explicit, use it. Otherwise use current logged in user.
    final String? targetUserId = (widget.userId != null && widget.userId!.isNotEmpty)
        ? widget.userId
        : currentUid;

    // Determine Ownership
    final bool isOwner = (currentUid != null && targetUserId == currentUid);

    // Auto-switch to Editor tab (0) if it's the owner and we haven't done it yet
    if (isOwner && !_hasDefaultedTab) {
      // Only switch if we are currently on Fanzines (1), which is the default
      if (_currentIndex == 1) {
        // We can't setState during build, so we schedule it
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _currentIndex = 0;
              _hasDefaultedTab = true;
            });
          }
        });
      } else {
        _hasDefaultedTab = true;
      }
    }

    // Handling cases where no user is found
    if (!userProvider.isLoading && targetUserId == null) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: LoginWidget(onTap: () => context.go('/register')),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: false,
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Profile Widget (Fixed Height)
                if (targetUserId != null)
                  SizedBox(
                    height: 340,
                    child: ProfileWidget(
                      targetUserId: targetUserId,
                      currentIndex: _currentIndex,
                      onEditorTapped: () => setState(() => _currentIndex = 0),
                      onFanzinesTapped: () => setState(() => _currentIndex = 1),
                      onPagesTapped: () => setState(() => _currentIndex = 2),
                    ),
                  ),

                const SizedBox(height: 16),

                // 2. The Content Grid
                if (targetUserId != null)
                  _buildContentGrid(targetUserId, isOwner, userProvider.isEditor),

                const SizedBox(height: 32),

                // 3. Bottom Widget (Navigation or Login Call-to-Action)
                if (!isOwner)
                  userProvider.isLoggedIn
                      ? const FanzineWidget()
                      : Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: LoginWidget(onTap: () => context.go('/register'))
                      )
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentGrid(String targetUserId, bool isOwner, bool isEditor) {
    // If non-owner tries to access Editor tab, force show Fanzines or empty
    int effectiveIndex = _currentIndex;
    if (!isOwner && effectiveIndex == 0) effectiveIndex = 1;

    // --- TAB 1: FANZINES (Consumed Content / Feed) ---
    if (effectiveIndex == 1) {
      Query fanzineQuery = FirebaseFirestore.instance
          .collection('fanzines')
          .where('editorId', isEqualTo: targetUserId)
          .orderBy('creationDate', descending: true);

      return StreamBuilder<QuerySnapshot>(
          stream: fanzineQuery.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const SizedBox(height: 100, child: Center(child: Text("No fanzines found.")));

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // CHANGED to 3 columns
                childAspectRatio: 5 / 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final title = data['title'] ?? 'Untitled';
                return Container(
                  // UPDATED: Removed circular border radius
                  decoration: const BoxDecoration(color: Colors.blueAccent),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(8),
                  child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                );
              },
            );
          }
      );
    }

    // --- TAB 0 (Editor) & TAB 2 (Pages) ---
    Query query;
    if (effectiveIndex == 0) {
      // Editor Tab: Show Fanzines to Edit
      query = FirebaseFirestore.instance.collection('fanzines').where('editorId', isEqualTo: targetUserId).orderBy('creationDate', descending: true);
    } else {
      // Pages Tab: Show Uploaded Images
      query = FirebaseFirestore.instance.collection('images').where('uploaderId', isEqualTo: targetUserId).orderBy('timestamp', descending: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {

        // --- EDITOR DASHBOARD BUTTONS (Only if Owner & Editor & Tab 0) ---
        final buttons = <Widget>[];
        if (effectiveIndex == 0 && isOwner) {
          if (isEditor) {
            buttons.add(TextButton(style: _blueButtonStyle, onPressed: () => _showNewFanzineModal(targetUserId), child: const Text("make new fanzine", textAlign: TextAlign.center, style: TextStyle(color: Colors.white))));
          } else {
            buttons.add(Container(padding: const EdgeInsets.all(8), color: Colors.red[100], alignment: Alignment.center, child: const Text("You are not an editor.", textAlign: TextAlign.center)));
          }
          // CHANGED: Use context.pushNamed('settings') for GoRouter navigation
          // UPDATED: Changed style to be square (removed default rounded button style if any, but TextButton is usually rectangular, ensuring square shape with explicit shape)
          buttons.add(TextButton(style: TextButton.styleFrom(backgroundColor: Colors.grey, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), onPressed: () => context.pushNamed('settings'), child: const Text("settings", textAlign: TextAlign.center, style: TextStyle(color: Colors.white))));
        }

        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];
        final totalItems = buttons.length + docs.length;

        if (totalItems == 0) return const SizedBox(height: 100, child: Center(child: Text("No content found.")));

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, // CHANGED to 3 columns
            childAspectRatio: 5 / 8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            // Render Buttons first
            if (index < buttons.length) return buttons[index];

            final docIndex = index - buttons.length;
            final data = docs[docIndex].data() as Map<String, dynamic>;

            if (effectiveIndex == 0) {
              // Editor: List of Fanzines
              final title = data['title'] ?? 'Untitled';
              return TextButton(
                style: _blueButtonStyle,
                // CHANGED: Use context.pushNamed('fanzineEditor', ...) for GoRouter navigation
                onPressed: () {
                  if (isOwner) {
                    context.pushNamed('fanzineEditor', pathParameters: {'fanzineId': docs[docIndex].id});
                  }
                },
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
              );
            } else {
              // Pages: List of Images
              final url = data['fileUrl'] ?? '';
              if (url.isEmpty) return const SizedBox();
              return GestureDetector(
                onTap: () {
                  showDialog(context: context, builder: (_) => ImageViewModal(imageUrl: url, imageText: data['text'], shortCode: data['shortCode'], imageId: docs[docIndex].id));
                },
                // UPDATED: Replaced ClipRRect with ClipRect (removed rounded corners)
                child: ClipRect(
                    child: Image.network(url, fit: BoxFit.cover)
                ),
              );
            }
          },
        );
      },
    );
  }
}