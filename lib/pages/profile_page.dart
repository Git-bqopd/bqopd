import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../blocs/profile/profile_bloc.dart';
import '../repositories/user_repository.dart';
import '../repositories/engagement_repository.dart';
import '../services/user_provider.dart';
import '../services/username_service.dart';
import '../services/user_bootstrap.dart';
import '../widgets/profile_widget.dart';
import '../widgets/page_wrapper.dart';
import '../widgets/image_upload_modal.dart';
import '../widgets/new_fanzine_modal.dart';

class ProfilePage extends StatelessWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUid = userProvider.currentUserId;
    final targetUserId = userId ?? currentUid;

    if (!userProvider.isLoading && targetUserId == null) {
      return const Scaffold(body: Center(child: Text("Please log in.")));
    }

    final queryParams = GoRouterState.of(context).uri.queryParameters;
    final initialTab = queryParams['tab'];
    final initialDrafts = queryParams['drafts'] == 'true';

    return BlocProvider(
      create: (context) => ProfileBloc(
        userRepository: context.read<UserRepository>(),
        engagementRepository: context.read<EngagementRepository>(),
      )..add(LoadProfileRequested(
        userId: targetUserId!,
        currentAuthId: currentUid ?? '',
        isViewerModerator: userProvider.isModerator,
        isViewerCurator: userProvider.isCurator,
        initialTab: initialTab,
      )),
      child: _ProfilePageView(initialDrafts: initialDrafts),
    );
  }
}

class _ProfilePageView extends StatefulWidget {
  final bool initialDrafts;
  const _ProfilePageView({this.initialDrafts = false});

  @override
  State<_ProfilePageView> createState() => _ProfilePageViewState();
}

class _ProfilePageViewState extends State<_ProfilePageView> {
  bool _showDrafts = false;
  int _curatorSubTabIndex = 0;
  bool _isUploadingPdf = false;

  @override
  void initState() {
    super.initState();
    _showDrafts = widget.initialDrafts;
  }

  bool _canEdit(Map<String, dynamic> userData) {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;
    if (userData['uid'] == currentUid) return true;
    final managers = List<String>.from(userData['managers'] ?? []);
    if ((userData['isManaged'] == true) && managers.contains(currentUid)) {
      return true;
    }
    return false;
  }

  void _showImageUpload(String userId) {
    showDialog(context: context, barrierDismissible: false, builder: (_) => ImageUploadModal(userId: userId));
  }

  void _showMakerCreateModal(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => MakerCreateModal(
        onSingleImage: () => _createFolio(userId, isSingleImage: true),
        onCreateFolio: () => _createFolio(userId, isSingleImage: false),
      ),
    );
  }

  void _showNewFanzineModal(String userId) {
    showDialog(context: context, barrierDismissible: false, builder: (_) => NewFanzineModal(userId: userId));
  }

  Future<void> _createFolio(String userId, {bool isSingleImage = false}) async {
    try {
      final db = FirebaseFirestore.instance;
      final folioRef = db.collection('fanzines').doc();
      final shortCode = folioRef.id.substring(0, 7);
      await folioRef.set({
        'title': isSingleImage ? 'Single Image' : 'New Folio',
        'ownerId': userId,
        'editorId': userId,
        'editors': [],
        'status': 'working',
        'processingStatus': 'complete',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'folio',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': false,
      });
      if (mounted) context.push('/editor/${folioRef.id}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _createCalendarFanzine(String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final fanzineRef = db.collection('fanzines').doc();
      final shortCode = fanzineRef.id.substring(0, 7);
      await fanzineRef.set({
        'title': 'Convention Calendar 2026',
        'ownerId': userId,
        'editorId': userId,
        'editors': [],
        'status': 'working',
        'processingStatus': 'complete',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'calendar',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
      });

      await fanzineRef.collection('pages').add({'pageNumber': 1, 'templateId': 'calendar_left', 'status': 'ready'});
      await fanzineRef.collection('pages').add({'pageNumber': 2, 'templateId': 'calendar_right', 'status': 'ready'});

      if (mounted) context.push('/editor/${fanzineRef.id}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _handlePdfUpload(String userId) async {
    if (_isUploadingPdf) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
      if (result != null) {
        setState(() => _isUploadingPdf = true);
        PlatformFile file = result.files.first;
        Uint8List? fileBytes = file.bytes;
        if (fileBytes != null) {
          final storageRef = FirebaseStorage.instance.ref().child('uploads/raw_pdfs/${file.name}');
          final metadata = SettableMetadata(contentType: 'application/pdf', customMetadata: {'uploaderId': userId, 'originalName': file.name});
          await storageRef.putData(fileBytes, metadata);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded "${file.name}". Curator processing started.')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload Error: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: BlocConsumer<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red));
          }
        },
        builder: (context, state) {
          if (state.isLoading) return const Center(child: CircularProgressIndicator());
          if (state.userData == null) return const Center(child: Text("Profile not found."));

          final userData = state.userData!;
          final targetUserId = userData['uid'];
          final isOwner = context.read<UserProvider>().currentUserId == targetUserId;
          final canEditProfile = _canEdit(userData);
          final activeTab = state.visibleTabs.isEmpty ? 'collection' : state.visibleTabs[state.currentTabIndex];

          return SafeArea(
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
                        userData: userData,
                        profileUid: targetUserId,
                        isMe: isOwner,
                        isFollowing: state.isFollowing,
                        onFollowToggle: () => context.read<ProfileBloc>().add(ToggleFollowRequested()),
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProfileTabsDelegate(
                      child: SizedBox(
                        height: 50,
                        child: ProfileNavBar(
                          tabTitles: state.visibleTabs,
                          currentIndex: state.currentTabIndex,
                          onTabChanged: (idx) {
                            context.read<ProfileBloc>().add(ChangeTabRequested(idx));
                            setState(() { _showDrafts = false; _curatorSubTabIndex = 0; });
                          },
                          canEdit: canEditProfile,
                          onUploadImage: () => _showImageUpload(targetUserId),
                        ),
                      ),
                    ),
                  ),

                  if (activeTab == 'curator')
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _isUploadingPdf ? null : () => _handlePdfUpload(targetUserId),
                                child: Text(_isUploadingPdf ? "uploading..." : "upload PDF", style: const TextStyle(color: Colors.black)),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("curator", 0),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("publisher", 1),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("entities", 2),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (activeTab == 'maker' && isOwner)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () => _showMakerCreateModal(targetUserId),
                                child: const Text("make", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = false),
                                child: Text("published", style: TextStyle(color: !_showDrafts ? Colors.black : Colors.grey, fontWeight: !_showDrafts ? FontWeight.bold : FontWeight.normal, decoration: !_showDrafts ? TextDecoration.underline : null)),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = true),
                                child: Text("drafts", style: TextStyle(color: _showDrafts ? Colors.black : Colors.grey, fontWeight: _showDrafts ? FontWeight.bold : FontWeight.normal, decoration: _showDrafts ? TextDecoration.underline : null)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (activeTab == 'pages' && isOwner)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () => _showImageUpload(targetUserId),
                                child: const Text("upload", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = false),
                                child: Text("published", style: TextStyle(color: !_showDrafts ? Colors.black : Colors.grey, fontWeight: !_showDrafts ? FontWeight.bold : FontWeight.normal, decoration: !_showDrafts ? TextDecoration.underline : null)),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = true),
                                child: Text("pending", style: TextStyle(color: _showDrafts ? Colors.black : Colors.grey, fontWeight: _showDrafts ? FontWeight.bold : FontWeight.normal, decoration: _showDrafts ? TextDecoration.underline : null)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  _buildContentSliver(targetUserId, isOwner, activeTab),
                  const SliverToBoxAdapter(child: SizedBox(height: 64)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubTab(String label, int index) {
    final isActive = _curatorSubTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _curatorSubTabIndex = index),
      child: Text(label, style: TextStyle(color: isActive ? Colors.black : Colors.grey, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, decoration: isActive ? TextDecoration.underline : null)),
    );
  }

  Widget _buildContentSliver(String targetUserId, bool isOwner, String activeTab) {
    Stream<List<QueryDocumentSnapshot>>? stream;

    switch (activeTab) {
      case 'curator':
        if (_curatorSubTabIndex == 2) {
          return _buildEntitiesSubView();
        }
        stream = FirebaseFirestore.instance.collection('fanzines').snapshots().map((snap) {
          final List<QueryDocumentSnapshot> filtered = snap.docs.where((doc) {
            final data = doc.data();
            final hasSource = data.containsKey('sourceFile');
            final isLive = data['status'] == 'live';

            if (_curatorSubTabIndex == 0) {
              return hasSource && !isLive;
            } else if (_curatorSubTabIndex == 1) {
              final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
              return (!hasSource || isLive) && (owner == targetUserId || (data['editors'] as List? ?? []).contains(targetUserId));
            } else {
              return false;
            }
          }).toList();
          filtered.sort((a, b) {
            final aT = (a.data() as Map)['creationDate'] as Timestamp?;
            final bT = (b.data() as Map)['creationDate'] as Timestamp?;
            return (bT ?? Timestamp.now()).compareTo(aT ?? Timestamp.now());
          });
          return filtered;
        });
        break;

      case 'maker':
        stream = FirebaseFirestore.instance.collection('fanzines').snapshots().map((snap) {
          return snap.docs.where((doc) {
            final data = doc.data();
            if (data['type'] != 'folio' && data['type'] != 'calendar') return false;

            // Legacy Support: Check ownerId, editorId, and uploaderId
            final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
            if (owner != targetUserId) return false;

            final isLive = data['status'] == 'live' || data['status'] == 'published';
            return _showDrafts ? !isLive : isLive;
          }).toList();
        });
        break;

      case 'pages':
        stream = FirebaseFirestore.instance.collection('images').where('uploaderId', isEqualTo: targetUserId).snapshots().map((snap) {
          return snap.docs.where((doc) {
            final data = doc.data();
            final isPending = data['status'] == 'pending';
            return _showDrafts ? isPending : !isPending;
          }).toList();
        });
        break;

      default:
        return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Coming Soon"))));
    }

    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: stream,
      builder: (context, snapshot) {
        final List<Widget> buttons = [];
        // Publisher creation buttons
        if (activeTab == 'curator' && _curatorSubTabIndex == 1 && isOwner) {
          buttons.add(_QuickActionTile(label: "make new fanzine", color: Colors.blueAccent, onTap: () => _showNewFanzineModal(targetUserId)));
          buttons.add(_QuickActionTile(label: "con calendar", color: Colors.purple, onTap: () => _createCalendarFanzine(targetUserId)));
          buttons.add(_QuickActionTile(label: "settings", color: Colors.grey, onTap: () => context.pushNamed('settings')));
        }

        if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        final docs = snapshot.data!;

        if (docs.isEmpty && buttons.isEmpty) return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No items found"))));

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index < buttons.length) return buttons[index];
              final docIndex = index - buttons.length;
              final data = docs[docIndex].data() as Map<String, dynamic>;
              return _FanzineCoverTile(fanzineId: docs[docIndex].id, title: data['title'] ?? 'Untitled', shouldEdit: activeTab == 'curator' || activeTab == 'maker');
            }, childCount: docs.length + buttons.length),
          ),
        );
      },
    );
  }

  Widget _buildEntitiesSubView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').where('status', whereIn: ['draft', 'working']).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));

        final Map<String, int> entityCounts = {};
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final entities = List<String>.from(data['draftEntities'] ?? []);
          for (var name in entities) {
            entityCounts[name] = (entityCounts[name] ?? 0) + 1;
          }
        }

        if (entityCounts.isEmpty) return const SliverToBoxAdapter(child: Center(child: Text("No entities found.")));

        final sortedNames = entityCounts.keys.toList()..sort((a, b) => entityCounts[b]!.compareTo(entityCounts[a]!));

        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return _EntityRow(name: sortedNames[index], count: entityCounts[sortedNames[index]]!);
            }, childCount: sortedNames.length),
          ),
        );
      },
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionTile({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: color,
        padding: const EdgeInsets.all(8),
        child: Center(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
      ),
    );
  }
}

class _EntityRow extends StatelessWidget {
  final String name;
  final int count;
  const _EntityRow({required this.name, required this.count});

  @override
  Widget build(BuildContext context) {
    final handle = normalizeHandle(name);
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usernames').doc(handle).snapshots(),
      builder: (context, snapshot) {
        Widget statusWidget;
        if (!snapshot.hasData) {
          statusWidget = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String linkText = '/$handle';
          if (data['isAlias'] == true) linkText = '/$handle -> /${data['redirect'] ?? 'unknown'}';
          statusWidget = InkWell(
              onTap: () => context.go('/$handle'),
              child: Text(linkText, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline))
          );
        } else {
          statusWidget = Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => _createProfile(context, name), child: const Text("Create", style: TextStyle(color: Colors.green, fontSize: 11))),
            TextButton(onPressed: () => _createAlias(context, name), child: const Text("Alias", style: TextStyle(color: Colors.orange, fontSize: 11))),
          ]);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(children: [
            SizedBox(width: 30, child: Text("$count", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
            statusWidget,
          ]),
        );
      },
    );
  }

  Future<void> _createProfile(BuildContext context, String name) async {
    String first = name; String last = "";
    if (name.contains(' ')) { final parts = name.split(' '); first = parts.first; last = parts.sublist(1).join(' '); }
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Editor Widget");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final target = await showDialog<String>(context: context, builder: (c) {
      final controller = TextEditingController();
      return AlertDialog(title: Text("Create Alias for '$name'"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Enter EXISTING username (target):"), TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")), TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))]);
    });
    if (target == null || target.isEmpty) return;
    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}

class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ProfileTabsDelegate({required this.child});
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Material(elevation: overlapsContent ? 4 : 0, child: child);
  @override double get maxExtent => 50.0;
  @override double get minExtent => 50.0;
  @override bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) => true;
}

class _FanzineCoverTile extends StatelessWidget {
  final String fanzineId;
  final String title;
  final bool shouldEdit;

  const _FanzineCoverTile({required this.fanzineId, required this.title, this.shouldEdit = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(shouldEdit ? '/editor/$fanzineId' : '/reader/$fanzineId'),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.grey[200], child: const Icon(Icons.menu_book, color: Colors.black12, size: 40)),
            Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), color: Colors.black54, child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis))),
          ],
        ),
      ),
    );
  }
}