import 'dart:async';
import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../services/user_provider.dart';
import '../widgets/profile_widget.dart'; // Contains ProfileHeader & ProfileNavBar
import '../widgets/new_fanzine_modal.dart';
import '../widgets/image_view_modal.dart';
import '../widgets/login_widget.dart';
import '../widgets/image_upload_modal.dart';

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

  // Local state for Pages tab sub-filter
  // false = published (default), true = drafts (pending)
  bool _showDrafts = false;

  // Data fetching state
  Map<String, dynamic>? _userData;
  bool _isLoadingData = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadAllData();
    }
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoadingData = true;
      _errorMessage = null;
    });

    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    final targetId = widget.userId ?? currentUid;

    if (targetId == null) {
      if (mounted) setState(() => _isLoadingData = false);
      return;
    }

    // 1. Fetch User Data
    try {
      if (currentUid != null && targetId == currentUid) {
        // Viewing Self
        if (provider.userProfile != null) {
          _userData = provider.userProfile;
        } else {
          // Wait for provider? Or fetch directly. Fetching directly is safer here.
          final doc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(targetId)
              .get();
          if (doc.exists) _userData = doc.data();
        }
      } else {
        // Viewing Others
        final doc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(targetId)
            .get();
        if (doc.exists) {
          _userData = doc.data();
        } else {
          _errorMessage = "User not found";
        }
      }

      // Sync URL vanity check
      if (_userData != null) {
        _syncUrl(_userData!['username']);
      }
    } catch (e) {
      _errorMessage = "Error loading user: $e";
    }

    // 2. Determine Tab
    await _determineInitialTab(targetId);

    if (mounted) setState(() => _isLoadingData = false);
  }

  void _syncUrl(String? username) {
    if (username == null || username.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final router = GoRouter.of(context);
        final currentPath = router.routerDelegate.currentConfiguration.uri.path;
        final targetPath = '/$username';
        if (currentPath != targetPath && currentPath != '/profile') {
          // Only redirect if we are on a generic route and want a vanity one
          router.go(targetPath);
        }
      } catch (_) {}
    });
  }

  Future<void> _determineInitialTab(String targetId) async {
    try {
      final mentionsSnap = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('mentionedUsers', arrayContains: 'user:$targetId')
          .limit(1)
          .get();

      if (mentionsSnap.docs.isNotEmpty) {
        if (mounted) setState(() => _currentIndex = 4); // Mentions
        return;
      }

      final editorSnap = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('editorId', isEqualTo: targetId)
          .limit(1)
          .get();

      if (editorSnap.docs.isNotEmpty) {
        if (mounted) setState(() => _currentIndex = 0); // Editor
        return;
      }
    } catch (_) {}

    if (mounted) setState(() => _currentIndex = 5); // Default to Collection
  }

  void _showNewFanzineModal(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewFanzineModal(userId: userId),
    );
  }

  void _showImageUpload(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageUploadModal(userId: userId),
    );
  }

  bool _canEdit(String profileUid) {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;
    if (profileUid == currentUid) return true;
    final managers = List<String>.from(_userData?['managers'] ?? []);
    if ((_userData?['isManaged'] == true) && managers.contains(currentUid))
      return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUid = userProvider.currentUserId;
    final targetUserId = widget.userId ?? currentUid;

    // Login Wall
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

    if (_isLoadingData || _userData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool isOwner = (currentUid != null && targetUserId == currentUid);
    final bool canEditProfile = _canEdit(targetUserId!);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 900,
          scroll: false, // CustomScrollView handles scrolling
          padding: EdgeInsets.zero, // Handle padding inside slivers
          child: CustomScrollView(
            slivers: [
              // 1. Profile Header (Scrolls naturally)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ProfileHeader(
                    userData: _userData!,
                    profileUid: targetUserId,
                    isMe: isOwner,
                  ),
                ),
              ),

              // 2. Sticky Tab Bar
              SliverPersistentHeader(
                pinned: true,
                delegate: _ProfileTabsDelegate(
                  child: SizedBox(
                    height: 50, // Force height to match minExtent/maxExtent
                    child: ProfileNavBar(
                      currentIndex: _currentIndex ?? 5,
                      onTabChanged: (idx) =>
                          setState(() {
                            _currentIndex = idx;
                            // Reset drafts view when switching tabs
                            if (idx != 1) _showDrafts = false;
                          }),
                      canEdit: canEditProfile,
                      onUploadImage: () => _showImageUpload(targetUserId),
                    ),
                  ),
                ),
              ),

              // 2.5 Secondary Toolbar (Pages Tab Only) - Also Sticky
              // Only show if user is viewing their own profile (isOwner) AND on 'pages' tab
              if (_currentIndex == 1 && canEditProfile && isOwner)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ProfileTabsDelegate(
                    child: Container(
                      height: 50, // Match the delegate's extent
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                            bottom: BorderSide(color: Colors.black12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _showImageUpload(targetUserId),
                            child: const Text("upload image",
                                style: TextStyle(
                                    fontWeight: FontWeight.normal, // No longer bold
                                    color: Colors.black)),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text("|",
                                style: TextStyle(color: Colors.grey)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showDrafts = false),
                            child: Text(
                              "published pages",
                              style: TextStyle(
                                color: !_showDrafts ? Colors.black : Colors.grey, // Active color logic
                                fontWeight: !_showDrafts ? FontWeight.bold : FontWeight.normal,
                                decoration: !_showDrafts ? TextDecoration.underline : null,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text("|",
                                style: TextStyle(color: Colors.grey)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showDrafts = true),
                            child: Text(
                              "draft pages",
                              style: TextStyle(
                                color: _showDrafts ? Colors.black : Colors.grey, // Active color logic
                                fontWeight: _showDrafts ? FontWeight.bold : FontWeight.normal,
                                decoration: _showDrafts ? TextDecoration.underline : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. Spacing
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // 4. Content Grid
              _buildContentSliver(
                  targetUserId, isOwner, userProvider.isEditor),

              // 5. Bottom Padding
              const SliverToBoxAdapter(child: SizedBox(height: 64)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentSliver(
      String targetUserId, bool isOwner, bool isEditor) {
    Stream<List<QueryDocumentSnapshot>>? stream;
    Widget? placeholder;

    // ... (Existing logic for selecting stream source remains the same) ...
    // Copying the switch logic from previous implementation
    switch (_currentIndex) {
      case 0: // EDITOR
        if (!isOwner && !isEditor)
          return const SliverToBoxAdapter(child: SizedBox());
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('editorId', isEqualTo: targetUserId)
            .orderBy('creationDate', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;
      case 1: // PAGES
        Query query = FirebaseFirestore.instance
            .collection('images')
            .where('uploaderId', isEqualTo: targetUserId);

        // Fetch ALL images for this user, then filter client-side.
        // This avoids complex index requirements and handles legacy data (missing status field).
        stream = query
            .orderBy('timestamp', descending: true)
            .snapshots()
            .map((snap) {
          if (isOwner) {
            if (_showDrafts) {
              // Show only Pending
              return snap.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['status'] == 'pending';
              }).toList();
            } else {
              // Show Published (Approved OR Legacy/No Status)
              // Explicitly exclude 'pending', include everything else.
              return snap.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['status'] != 'pending';
              }).toList();
            }
          }
          // If not owner (viewing someone else), only show published
          return snap.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['status'] != 'pending';
          }).toList();
        });
        break;
      case 2: // WORKS
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('editorId', isEqualTo: targetUserId)
            .orderBy('creationDate', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;
      case 3: // COMMENTS
        placeholder = const Center(
            child: Text("Letters of Comment functionality coming soon."));
        break;
      case 4: // MENTIONS
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('mentionedUsers', arrayContains: 'user:$targetUserId')
            .orderBy('creationDate', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;
      case 5: // COLLECTION
        placeholder =
        const Center(child: Text("User collection coming soon."));
        break;
    }

    if (placeholder != null) {
      return SliverToBoxAdapter(
          child: SizedBox(height: 200, child: placeholder));
    }

    if (stream == null) return const SliverToBoxAdapter(child: SizedBox());

    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: stream,
      builder: (context, snapshot) {
        final buttons = <Widget>[];
        // Reconstruct Buttons
        if (_currentIndex == 0 && isOwner) {
          if (isEditor) {
            buttons.add(TextButton(
                style: TextButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero)),
                onPressed: () => _showNewFanzineModal(targetUserId),
                child: const Text("make new fanzine",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white))));
          }
          buttons.add(TextButton(
              style: TextButton.styleFrom(
                  backgroundColor: Colors.grey,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero)),
              onPressed: () => context.pushNamed('settings'),
              child: const Text("settings",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white))));
        }

        // --- ERROR HANDLING START ---
        if (snapshot.hasError) {
          final errorMsg = snapshot.error.toString();
          // Check for Firestore Index requirement
          if (errorMsg.contains('failed-precondition') ||
              errorMsg.contains('requires an index')) {
            final urlRegex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
            final match = urlRegex.firstMatch(errorMsg);
            final indexUrl = match?.group(0);

            return SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Database Index Required",
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                          "To filter this view properly, a Firestore index is needed.",
                          textAlign: TextAlign.center),
                      if (indexUrl != null) ...[
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => launchUrl(Uri.parse(indexUrl)),
                          child: const Text("Create Index"),
                        )
                      ] else
                        SelectableText(errorMsg,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            );
          }
          return SliverToBoxAdapter(child: Center(child: Text("Error: $errorMsg")));
        }
        // --- ERROR HANDLING END ---

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()));
        }

        final docs = snapshot.data ?? [];
        final totalItems = buttons.length + docs.length;

        if (totalItems == 0) {
          String emptyMsg = "No items found.";
          if (_currentIndex == 1 && isOwner) {
            emptyMsg = _showDrafts ? "No pending drafts." : "No published pages.";
          }
          return SliverToBoxAdapter(
              child: SizedBox(
                  height: 100,
                  child: Center(child: Text(emptyMsg))));
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 5 / 8,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                if (index < buttons.length) return buttons[index];

                final docIndex = index - buttons.length;
                final doc = docs[docIndex];
                final data = doc.data() as Map<String, dynamic>;
                final docId = doc.id;

                if (_currentIndex == 0 ||
                    _currentIndex == 2 ||
                    _currentIndex == 4) {
                  // Fanzines
                  return _FanzineCoverTile(
                    fanzineId: docId,
                    title: data['title'] ?? 'Untitled',
                    shouldEdit: _currentIndex == 0, // NEW: Conditional route
                  );
                } else {
                  // Images
                  String? imageUrl = data['fileUrl'];
                  if (imageUrl == null || imageUrl.isEmpty)
                    return const SizedBox();

                  Widget imageWidget = ClipRect(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                        const Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.grey)),
                      ));

                  return GestureDetector(
                    onTap: () {
                      showDialog(
                          context: context,
                          builder: (_) => ImageViewModal(
                              imageUrl: imageUrl,
                              imageText: data['text'],
                              shortCode: data['shortCode'],
                              imageId: docId));
                    },
                    child: imageWidget,
                  );
                }
              },
              childCount: totalItems,
            ),
          ),
        );
      },
    );
  }
}

// Delegate for the Sticky Header
class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _ProfileTabsDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(elevation: overlapsContent ? 4 : 0, child: child);
  }

  @override
  double get maxExtent => 50.0; // Approx height of tab bar

  @override
  double get minExtent => 50.0;

  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) {
    // Rebuild if child changes (e.g. index updated)
    return true;
  }
}

// Updated helper to handle conditional navigation
class _FanzineCoverTile extends StatelessWidget {
  final String fanzineId;
  final String title;
  final bool shouldEdit; // Added field

  const _FanzineCoverTile({
    required this.fanzineId,
    required this.title,
    this.shouldEdit = false, // Default to Reader
  });

  Future<String?> _fetchCoverUrl() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(fanzineId)
          .collection('pages')
          .orderBy('pageNumber')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final storagePath = data['storagePath'];
        if (storagePath != null && storagePath.toString().isNotEmpty) {
          try {
            return await FirebaseStorage.instance
                .ref(storagePath)
                .getDownloadURL();
          } catch (_) {}
        }
        return data['imageUrl'];
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _fetchCoverUrl(),
      builder: (context, snapshot) {
        final imageUrl = snapshot.data;
        return GestureDetector(
          onTap: () {
            // Conditional Routing based on tab context
            if (shouldEdit) {
              context.push('/editor/$fanzineId');
            } else {
              context.push('/reader/$fanzineId');
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null)
                  Image.network(imageUrl, fit: BoxFit.cover)
                else
                  const Center(
                      child: Icon(Icons.book, size: 40, color: Colors.grey)),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                    child: Text(
                      title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
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