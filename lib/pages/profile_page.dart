import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // Added for error link
import 'dart:async'; // Required for Stream manipulation

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
      // Prioritize Works if they exist (for entities like "The Comet")
      final mentionsSnap = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('mentionedUsers', arrayContains: 'user:$targetId')
          .limit(1)
          .get();

      if (mentionsSnap.docs.isNotEmpty) {
        if (mounted) setState(() { _currentIndex = 4; _isLoadingDefaults = false; }); // Default to Mentions for entities
        return;
      }

      final editorSnap = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('editorId', isEqualTo: targetId)
          .limit(1)
          .get();

      if (editorSnap.docs.isNotEmpty) {
        if (mounted) setState(() { _currentIndex = 0; _isLoadingDefaults = false; });
        return;
      }
    } catch (e) {
      // Ignore errors
    }

    if (mounted) {
      setState(() { _currentIndex = 5; _isLoadingDefaults = false; }); // Default to Collection
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
    Stream<List<QueryDocumentSnapshot>>? stream;
    Widget? placeholder;

    switch (_currentIndex) {
      case 0: // EDITOR (Created by this user)
      // Only show if owner or checking editor status?
      // Actually, public users should see what an Editor has created.
        if (!isOwner && !isEditor) return const SizedBox();
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('editorId', isEqualTo: targetUserId)
            .orderBy('creationDate', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;

      case 1: // PAGES (Images uploaded by this user)
        stream = FirebaseFirestore.instance
            .collection('images')
            .where('uploaderId', isEqualTo: targetUserId)
            .orderBy('timestamp', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;

      case 2: // WORKS (Edited BY this user)
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('editorId', isEqualTo: targetUserId)
            .orderBy('creationDate', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;

      case 3: // COMMENTS
        placeholder = const Center(child: Text("Letters of Comment functionality coming soon."));
        break;

      case 4: // MENTIONS (Fanzines mentioning this entity/user)
      // CHANGED: Now querying FANZINES, not images.
      // This acts as the "What links here" / "Appears in" tab.
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('mentionedUsers', arrayContains: 'user:$targetUserId')
            .orderBy('creationDate', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;

      case 5: // COLLECTION
        placeholder = const Center(child: Text("User collection coming soon."));
        break;
    }

    if (placeholder != null) {
      return SizedBox(height: 200, child: placeholder);
    }

    if (stream == null) return const SizedBox();

    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: stream,
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

        // --- ERROR HANDLING START ---
        if (snapshot.hasError) {
          final errorMsg = snapshot.error.toString();
          // Check for Firestore Index requirement
          if (errorMsg.contains('failed-precondition') || errorMsg.contains('requires an index')) {
            // Try to extract URL
            final urlRegex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
            final match = urlRegex.firstMatch(errorMsg);
            final indexUrl = match?.group(0);

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Database Index Required", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text("To view this list sorted by date, a Firestore index is needed.", textAlign: TextAlign.center),
                    if (indexUrl != null) ...[
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => launchUrl(Uri.parse(indexUrl)),
                        child: const Text("Create Index"),
                      )
                    ] else
                      SelectableText(errorMsg, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            );
          }
          return Center(child: Text('Error: $errorMsg'));
        }
        // --- ERROR HANDLING END ---

        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data ?? [];
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
            final doc = docs[docIndex];
            final data = doc.data() as Map<String, dynamic>;
            final docId = doc.id;

            // Logic for displaying Fanzine Covers
            // Apply for Tab 0 (Editor), Tab 2 (Works), and Tab 4 (Mentions)
            if (_currentIndex == 0 || _currentIndex == 2 || _currentIndex == 4) {
              return _FanzineCoverTile(
                fanzineId: docId,
                title: data['title'] ?? 'Untitled',
              );
            } else {
              // Image/Page display (Tab 1, etc)
              String? imageUrl = data['fileUrl'];
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

// Simple Stream Merger helper
class StreamGroup {
  static Stream<T> merge<T>(List<Stream<T>> streams) {
    StreamController<T> controller = StreamController<T>();
    for (var stream in streams) {
      stream.listen(controller.add, onError: controller.addError);
    }
    return controller.stream;
  }
}

class _FanzineCoverTile extends StatelessWidget {
  final String fanzineId;
  final String title;

  const _FanzineCoverTile({required this.fanzineId, required this.title});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('fanzines')
          .doc(fanzineId)
          .collection('pages')
          .orderBy('pageNumber')
          .limit(1)
          .get(),
      builder: (context, snapshot) {
        String? imageUrl;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          imageUrl = snapshot.data!.docs.first['imageUrl'];
        }

        return GestureDetector(
          onTap: () => context.push('/reader/$fanzineId'),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null)
                  Image.network(imageUrl, fit: BoxFit.cover)
                else
                  const Center(child: Icon(Icons.book, size: 40, color: Colors.grey)),

                // Gradient for text readability
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}