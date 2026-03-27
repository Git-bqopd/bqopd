import 'dart:async';
import 'dart:typed_data';
import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
  final bool _isLoadingDefaults = true;

  // Local state for Pages tab sub-filter
  // false = published (default), true = drafts (pending)
  bool _showDrafts = false;

  // Local state for Editor tab sub-filter
  // 0 = curator (in-process), 1 = publisher (live)
  int _editorSubTabIndex = 0;

  // Data fetching state
  Map<String, dynamic>? _userData;
  bool _isLoadingData = true;
  bool _isUploadingPdf = false;
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
    if (!mounted) return;
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

    try {
      if (currentUid != null && targetId == currentUid) {
        if (provider.userProfile != null) {
          _userData = provider.userProfile;
        } else {
          final doc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(targetId)
              .get();
          if (doc.exists) _userData = doc.data();
        }
      } else {
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

      if (_userData != null) {
        _syncUrl(_userData!['username']);
      }
    } catch (e) {
      _errorMessage = "Error loading user: $e";
    }

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

  Future<void> _createCalendarFanzine(String userId) async {
    setState(() => _isLoadingData = true);
    try {
      final db = FirebaseFirestore.instance;
      final fanzineRef = db.collection('fanzines').doc();

      final shortCode = fanzineRef.id.substring(0, 7);

      await fanzineRef.set({
        'title': 'Convention Calendar 2026',
        'editorId': userId,
        'status': 'working',
        'processingStatus': 'complete',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'calendar',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
      });

      await fanzineRef.collection('pages').add({
        'pageNumber': 1,
        'templateId': 'calendar_left',
        'status': 'ready',
      });
      await fanzineRef.collection('pages').add({
        'pageNumber': 2,
        'templateId': 'calendar_right',
        'status': 'ready',
      });

      if (mounted) context.push('/editor/${fanzineRef.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<void> _handlePdfUpload(String userId) async {
    if (_isUploadingPdf) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null) {
        setState(() => _isUploadingPdf = true);

        PlatformFile file = result.files.first;
        Uint8List? fileBytes = file.bytes;
        String fileName = file.name;

        if (fileBytes != null) {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('uploads/raw_pdfs/$fileName');

          final metadata = SettableMetadata(
            contentType: 'application/pdf',
            customMetadata: {
              'uploaderId': userId,
              'originalName': fileName,
            },
          );

          await storageRef.putData(fileBytes, metadata);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Uploaded "$fileName". Curator processing started.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPdf = false);
    }
  }

  bool _canEdit(String profileUid) {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;
    if (profileUid == currentUid) return true;
    final managers = List<String>.from(_userData?['managers'] ?? []);
    if ((_userData?['isManaged'] == true) && managers.contains(currentUid)) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUid = userProvider.currentUserId;
    final targetUserId = widget.userId ?? currentUid;

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

    // --- SIMPLE VISIBILITY LOGIC ---
    final bool isThisUserAnEditor = _userData?['Editor'] == true || _userData?['isEditor'] == true;
    final bool amIAnEditor = (userProvider.isEditor == true) || (isOwner && isThisUserAnEditor);
    final bool showEditorTab = isThisUserAnEditor && amIAnEditor;

    // --- DYNAMIC TAB MAPPING ---
    // We map the visible titles to your absolute index numbers (0=Editor, 1=Pages)
    final List<Map<String, dynamic>> tabs = [];
    if (showEditorTab) tabs.add({'title': 'editor', 'id': 0});
    tabs.addAll([
      {'title': 'pages', 'id': 1},
      {'title': 'works', 'id': 2},
      {'title': 'comments', 'id': 3},
      {'title': 'mentions', 'id': 4},
      {'title': 'collection', 'id': 5},
    ]);

    final List<String> tabTitles = tabs.map((t) => t['title'] as String).toList();

    // Find the current array position for the NavBar based on your absolute index
    int navIndex = tabs.indexWhere((t) => t['id'] == (_currentIndex ?? 5));
    if (navIndex == -1) {
      navIndex = tabs.length - 1; // Fallback to collection if the requested tab is hidden
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = tabs[navIndex]['id'] as int);
      });
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 900,
          scroll: false,
          padding: EdgeInsets.zero,
          child: CustomScrollView(
            slivers: [
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

              SliverPersistentHeader(
                pinned: true,
                delegate: _ProfileTabsDelegate(
                  child: SizedBox(
                    height: 50,
                    child: ProfileNavBar(
                      tabTitles: tabTitles, // ACTUALLY PASS THE DYNAMIC LIST!
                      currentIndex: navIndex, // Pass the mapped array index
                      onTabChanged: (idx) => setState(() {
                        _currentIndex = tabs[idx]['id'] as int; // Map back to your absolute index
                        if (_currentIndex != 1) _showDrafts = false;
                        if (_currentIndex != 0) _editorSubTabIndex = 0;
                      }),
                      canEdit: canEditProfile,
                      onUploadImage: () => _showImageUpload(targetUserId),
                    ),
                  ),
                ),
              ),

              // Sub-navigation for Editor Tab
              if (_currentIndex == 0 && canEditProfile && isOwner)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ProfileTabsDelegate(
                    child: Container(
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border:
                        Border(bottom: BorderSide(color: Colors.black12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _isUploadingPdf
                                ? null
                                : () => _handlePdfUpload(targetUserId),
                            child: Text(
                              _isUploadingPdf ? "uploading..." : "upload PDF",
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text("|", style: TextStyle(color: Colors.grey)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _editorSubTabIndex = 0),
                            child: Text(
                              "curator",
                              style: TextStyle(
                                color: _editorSubTabIndex == 0
                                    ? Colors.black
                                    : Colors.grey,
                                fontWeight: _editorSubTabIndex == 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                decoration: _editorSubTabIndex == 0
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text("|", style: TextStyle(color: Colors.grey)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _editorSubTabIndex = 1),
                            child: Text(
                              "publisher",
                              style: TextStyle(
                                color: _editorSubTabIndex == 1
                                    ? Colors.black
                                    : Colors.grey,
                                fontWeight: _editorSubTabIndex == 1
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                decoration: _editorSubTabIndex == 1
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Sub-navigation for Pages Tab
              if (_currentIndex == 1 && canEditProfile && isOwner)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ProfileTabsDelegate(
                    child: Container(
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border:
                        Border(bottom: BorderSide(color: Colors.black12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _showImageUpload(targetUserId),
                            child: const Text("upload image",
                                style: TextStyle(color: Colors.black)),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text("|", style: TextStyle(color: Colors.grey)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showDrafts = false),
                            child: Text(
                              "published pages",
                              style: TextStyle(
                                color:
                                !_showDrafts ? Colors.black : Colors.grey,
                                fontWeight: !_showDrafts
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                decoration: !_showDrafts
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text("|", style: TextStyle(color: Colors.grey)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showDrafts = true),
                            child: Text(
                              "draft pages",
                              style: TextStyle(
                                color: _showDrafts ? Colors.black : Colors.grey,
                                fontWeight: _showDrafts
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                decoration: _showDrafts
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              _buildContentSliver(targetUserId, isOwner, amIAnEditor),

              const SliverToBoxAdapter(child: SizedBox(height: 64)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentSliver(String targetUserId, bool isOwner, bool isEditor) {
    Stream<List<QueryDocumentSnapshot>>? stream;
    Widget? placeholder;

    switch (_currentIndex) {
      case 0: // EDITOR
        if (!isOwner && !isEditor) {
          return const SliverToBoxAdapter(child: SizedBox());
        }

        // Fetch all user zines and filter client-side to avoid index requirements
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .snapshots()
            .map((snap) {
          final List<QueryDocumentSnapshot> filtered = snap.docs.where((doc) {
            final data = doc.data();

            final hasSourceFile = data.containsKey('sourceFile');
            final isLive = data['status'] == 'live';

            if (_editorSubTabIndex == 0) {
              // CURATOR: Show all in-process PDF zines that haven't gone live.
              // Mirroring the Dashboard logic: any zine not live that has a source file.
              return hasSourceFile && !isLive;
            } else {
              // PUBLISHER: Show zines that were manually created OR are now live.
              // Only show for the specific user being viewed.
              final isUserInvolved = data['editorId'] == targetUserId ||
                  data['uploaderId'] == targetUserId;
              if (!isUserInvolved) return false;
              return !hasSourceFile || isLive;
            }
          }).toList();

          // Memory sort by creationDate descending
          filtered.sort((a, b) {
            final aT = (a.data() as Map)['creationDate'] as Timestamp?;
            final bT = (b.data() as Map)['creationDate'] as Timestamp?;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          });

          return filtered;
        });
        break;
      case 1: // PAGES
        stream = FirebaseFirestore.instance
            .collection('images')
            .where('uploaderId', isEqualTo: targetUserId)
            .orderBy('timestamp', descending: true)
            .snapshots()
            .map((snap) {
          if (isOwner) {
            if (_showDrafts) {
              return snap.docs.where((doc) {
                final data = doc.data();
                return data['status'] == 'pending';
              }).toList();
            } else {
              return snap.docs.where((doc) {
                final data = doc.data();
                return data['status'] != 'pending';
              }).toList();
            }
          }
          return snap.docs.where((doc) {
            final data = doc.data();
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
        placeholder = const Center(child: Text("User collection coming soon."));
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
        if (_currentIndex == 0 && isOwner && _editorSubTabIndex == 1) {
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

            buttons.add(TextButton(
                style: TextButton.styleFrom(
                    backgroundColor: Colors.purple,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero)),
                onPressed: () => _createCalendarFanzine(targetUserId),
                child: const Text("con calendar",
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

        if (snapshot.hasError) {
          return SliverToBoxAdapter(
              child: Center(child: Text("Error: ${snapshot.error}")));
        }

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
          } else if (_currentIndex == 0 && isOwner) {
            emptyMsg = _editorSubTabIndex == 0
                ? "No zines in curator queue."
                : "No live fanzines.";
          }
          return SliverToBoxAdapter(
              child: SizedBox(height: 100, child: Center(child: Text(emptyMsg))));
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
                  return _FanzineCoverTile(
                    fanzineId: docId,
                    title: data['title'] ?? 'Untitled',
                    shouldEdit: _currentIndex == 0,
                  );
                } else {
                  String? imageUrl = data['fileUrl'];
                  if (imageUrl == null || imageUrl.isEmpty) {
                    return const SizedBox();
                  }

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
                    child: ClipRect(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                          const Center(
                              child: Icon(Icons.broken_image, color: Colors.grey)),
                        )),
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

class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ProfileTabsDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(elevation: overlapsContent ? 4 : 0, child: child);
  }

  @override
  double get maxExtent => 50.0;

  @override
  double get minExtent => 50.0;

  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) => true;
}

class _FanzineCoverTile extends StatelessWidget {
  final String fanzineId;
  final String title;
  final bool shouldEdit;

  const _FanzineCoverTile({
    required this.fanzineId,
    required this.title,
    this.shouldEdit = false,
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
        final bool isLoading =
            snapshot.connectionState == ConnectionState.waiting;
        final imageUrl = snapshot.data;

        return GestureDetector(
          onTap: () {
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
                else if (isLoading)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else
                // Improved Placeholder for unprocessed zines
                  Container(
                    color: Colors.grey[200],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pending_actions,
                            size: 40, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            "Ingesting...",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

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