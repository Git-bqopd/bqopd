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

class ProfilePage extends StatefulWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // TABS: 0=Editor, 1=Pages, 2=Works, 3=Comments, 4=Mentions, 5=Collection
  int? _currentIndex;
  bool _isLoadingDefaults = true;

  @override
  void initState() {
    super.initState();
    _determineInitialTab();
  }

  Future<void> _determineInitialTab() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = userProvider.currentUserId;
    final targetId = widget.userId ?? currentUid;

    if (targetId == null) {
      if (mounted) setState(() => _isLoadingDefaults = false);
      return;
    }

    try {
      final pagesSnap = await FirebaseFirestore.instance
          .collection('images')
          .where('uploaderId', isEqualTo: targetId)
          .limit(1)
          .get();

      if (pagesSnap.docs.isNotEmpty) {
        if (mounted) setState(() { _currentIndex = 1; _isLoadingDefaults = false; });
        return;
      }

      final worksSnap = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('editorId', isEqualTo: targetId)
          .limit(1)
          .get();

      if (worksSnap.docs.isNotEmpty) {
        if (mounted) setState(() { _currentIndex = 2; _isLoadingDefaults = false; });
        return;
      }
    } catch (e) {
      // Ignore errors
    }

    if (mounted) {
      setState(() { _currentIndex = 5; _isLoadingDefaults = false; });
    }
  }

  void _showNewFanzineModal(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewFanzineModal(userId: userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUid = userProvider.currentUserId;
    final targetUserId = (widget.userId != null && widget.userId!.isNotEmpty)
        ? widget.userId
        : currentUid;

    final bool isOwner = (currentUid != null && targetUserId == currentUid);

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

    if (_isLoadingDefaults || _currentIndex == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                if (targetUserId != null)
                // Removed fixed height; ProfileWidget now enforces 8:5 aspect ratio
                // It will take full width of PageWrapper and calculate height accordingly.
                  ProfileWidget(
                    targetUserId: targetUserId,
                    currentIndex: _currentIndex!,
                    onTabChanged: (index) => setState(() => _currentIndex = index),
                  ),

                const SizedBox(height: 16),

                if (targetUserId != null)
                  _buildContentGrid(targetUserId, isOwner, userProvider.isEditor),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentGrid(String targetUserId, bool isOwner, bool isEditor) {
    Query? query;
    Widget? placeholder;

    switch (_currentIndex) {
      case 0: // EDITOR
        if (!isOwner) return const SizedBox();
        query = FirebaseFirestore.instance
            .collection('fanzines')
            .where('editorId', isEqualTo: targetUserId)
            .orderBy('creationDate', descending: true);
        break;
      case 1: // PAGES
        query = FirebaseFirestore.instance
            .collection('images')
            .where('uploaderId', isEqualTo: targetUserId)
            .orderBy('timestamp', descending: true);
        break;
      case 2: // WORKS
        query = FirebaseFirestore.instance
            .collection('fanzines')
            .where('editorId', isEqualTo: targetUserId)
            .orderBy('creationDate', descending: true);
        break;
      case 3: // COMMENTS
        placeholder = const Center(child: Text("Letters of Comment functionality coming soon."));
        break;
      case 4: // MENTIONS
        query = FirebaseFirestore.instance
            .collection('images')
            .where('mentions', arrayContains: 'user:$targetUserId')
            .orderBy('timestamp', descending: true);
        break;
      case 5: // COLLECTION
        placeholder = const Center(child: Text("User collection coming soon."));
        break;
    }

    if (placeholder != null) {
      return SizedBox(height: 200, child: placeholder);
    }

    if (query == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        final buttons = <Widget>[];
        if (_currentIndex == 0 && isOwner) {
          if (isEditor) {
            buttons.add(TextButton(
                style: TextButton.styleFrom(backgroundColor: Colors.blueAccent, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                onPressed: () => _showNewFanzineModal(targetUserId),
                child: const Text("make new fanzine", textAlign: TextAlign.center, style: TextStyle(color: Colors.white))
            ));
          }
          buttons.add(TextButton(
              style: TextButton.styleFrom(backgroundColor: Colors.grey, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
              onPressed: () => context.pushNamed('settings'),
              child: const Text("settings", textAlign: TextAlign.center, style: TextStyle(color: Colors.white))
          ));
        }

        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];
        final totalItems = buttons.length + docs.length;

        if (totalItems == 0) return const SizedBox(height: 100, child: Center(child: Text("No items found.")));

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 5 / 8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index < buttons.length) return buttons[index];

            final docIndex = index - buttons.length;
            final data = docs[docIndex].data() as Map<String, dynamic>;
            final docId = docs[docIndex].id;

            String? imageUrl = data['fileUrl'];
            String? title = data['title'];

            if (_currentIndex == 0 || _currentIndex == 2) {
              return TextButton(
                style: TextButton.styleFrom(backgroundColor: Colors.blueAccent, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                onPressed: () {
                  if (_currentIndex == 0 && isOwner) {
                    context.pushNamed('fanzineEditor', pathParameters: {'fanzineId': docId});
                  }
                },
                child: Text(title ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
              );
            } else {
              if (imageUrl == null || imageUrl.isEmpty) return const SizedBox();
              return GestureDetector(
                onTap: () {
                  showDialog(context: context, builder: (_) => ImageViewModal(
                      imageUrl: imageUrl!,
                      imageText: data['text'],
                      shortCode: data['shortCode'],
                      imageId: docId
                  ));
                },
                child: ClipRect(
                    child: Image.network(imageUrl, fit: BoxFit.cover)
                ),
              );
            }
          },
        );
      },
    );
  }
}