import 'dart:async';
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
import '../widgets/image_view_modal.dart';
import '../widgets/comment_item.dart';

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
  int _indexSubTabIndex = 0;
  int _settingsSubTabIndex = 0;
  bool _isUploadingPdf = false;

  // Settings Tab Controllers
  final _loginZineController = TextEditingController();
  final _registerZineController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _showDrafts = widget.initialDrafts;
    _loadGlobalSettings();
  }

  @override
  void dispose() {
    _loginZineController.dispose();
    _registerZineController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('app_settings').doc('main_settings').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _loginZineController.text = data['login_zine_shortcode'] ?? '';
          _registerZineController.text = data['register_zine_shortcode'] ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _saveGlobalShortcodes() async {
    try {
      await FirebaseFirestore.instance.collection('app_settings').doc('main_settings').set({
        'login_zine_shortcode': _loginZineController.text,
        'register_zine_shortcode': _registerZineController.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  bool _canEdit(Map<String, dynamic> userData) {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) {
      return false;
    }
    if (userData['uid'] == currentUid) {
      return true;
    }
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
        onSingleImage: () {
          _showImageUpload(userId);
        },
        onCreateFolio: () => _createFolio(userId, isSingleImage: false),
        onCreateCalendar: () => _createCalendarFanzine(userId),
      ),
    );
  }

  void _showCatalogModal(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogModal(
        onUploadPdf: () => _handlePdfUpload(userId),
        onUploadImages: () => _createArchivalFanzine(userId),
      ),
    );
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
      if (mounted) {
        context.push('/editor/${folioRef.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _createArchivalFanzine(String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final fzRef = db.collection('fanzines').doc();
      final shortCode = fzRef.id.substring(0, 7);
      await fzRef.set({
        'title': 'Archival Work',
        'ownerId': userId,
        'editorId': userId,
        'editors': [],
        'status': 'working',
        'processingStatus': 'idle',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'ingested',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': false,
      });
      if (mounted) {
        context.push('/editor/${fzRef.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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

      if (mounted) {
        context.push('/editor/${fanzineRef.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _handlePdfUpload(String userId) async {
    if (_isUploadingPdf) {
      return;
    }
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded "${file.name}". Curator processing started.')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPdf = false);
      }
    }
  }

  Future<void> _handleCreateManagedProfile() async {
    if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a First and Last Name')));
      return;
    }
    try {
      await createManagedProfile(firstName: _firstNameController.text, lastName: _lastNameController.text, bio: _bioController.text);
      _firstNameController.clear();
      _lastNameController.clear();
      _bioController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Managed Profile Created!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating profile: $e')));
      }
    }
  }

  void _showCreateManagedProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create Managed Profile"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Create a profile for a historical figure or estate that you will manage."),
              const SizedBox(height: 16),
              TextField(controller: _firstNameController, decoration: const InputDecoration(labelText: "First Name", border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _lastNameController, decoration: const InputDecoration(labelText: "Last Name", border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: _bioController, decoration: const InputDecoration(labelText: "Bio (Optional)", border: OutlineInputBorder()), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () { Navigator.pop(context); _handleCreateManagedProfile(); }, child: const Text("Create")),
        ],
      ),
    );
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
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.userData == null) {
            return const Center(child: Text("Profile not found."));
          }

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
                            setState(() {
                              _showDrafts = false;
                              _curatorSubTabIndex = 0;
                              _indexSubTabIndex = 0;
                              _settingsSubTabIndex = 0;
                            });
                          },
                          canEdit: canEditProfile,
                          onUploadImage: () => _showImageUpload(targetUserId),
                        ),
                      ),
                    ),
                  ),

                  if (activeTab == 'settings')
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildSubTab("shortcodes", 0, type: 'settings'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("managed profiles", 1, type: 'settings'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("permissions", 2, type: 'settings'),
                            ],
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
                                onTap: () => _showCatalogModal(targetUserId),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.black)),
                                  child: Text(
                                    _isUploadingPdf ? "uploading..." : "catalog",
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _buildSubTab("curator", 0, type: 'curator'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("publisher", 1, type: 'curator'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("entities", 2, type: 'curator'),
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
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.black)),
                                  child: const Text("make",
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                                ),
                              ),
                              const SizedBox(width: 12),
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

                  if (activeTab == 'index')
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildSubTab("works", 0, type: 'index'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("mentions", 1, type: 'index'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("comments", 2, type: 'index'),
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

  Widget _buildSubTab(String label, int index, {required String type}) {
    int currentIdx;
    if (type == 'curator') {
      currentIdx = _curatorSubTabIndex;
    } else if (type == 'index') {
      currentIdx = _indexSubTabIndex;
    } else {
      currentIdx = _settingsSubTabIndex;
    }

    final isActive = currentIdx == index;
    return GestureDetector(
      onTap: () => setState(() {
        if (type == 'curator') {
          _curatorSubTabIndex = index;
        } else if (type == 'index') {
          _indexSubTabIndex = index;
        } else {
          _settingsSubTabIndex = index;
        }
      }),
      child: Text(label, style: TextStyle(color: isActive ? Colors.black : Colors.grey, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, decoration: isActive ? TextDecoration.underline : null)),
    );
  }

  Widget _buildContentSliver(String targetUserId, bool isOwner, String activeTab) {
    switch (activeTab) {
      case 'settings':
        return _buildSettingsSubView(targetUserId);
      case 'curator':
        if (_curatorSubTabIndex == 2) {
          return _buildEntitiesSubView();
        }
        return _buildCuratorSubView(targetUserId);
      case 'maker':
        return _MakerCombinedView(targetUserId: targetUserId, showDrafts: _showDrafts);
      case 'index':
        if (_indexSubTabIndex == 2) {
          return _UserCommentsView(userId: targetUserId);
        }
        return _buildIndexSubView(targetUserId);
      case 'collection':
        return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Collection Coming Soon"))));
      default:
        return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Coming Soon"))));
    }
  }

  Widget _buildCuratorSubView(String targetUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        final filtered = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final hasSource = data.containsKey('sourceFile');
          final isLive = data['status'] == 'live';
          if (_curatorSubTabIndex == 0) {
            return hasSource && !isLive;
          }
          final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
          return (!hasSource || isLive) && (owner == targetUserId || (data['editors'] as List? ?? []).contains(targetUserId));
        }).toList();
        filtered.sort((a, b) => ((b.data() as Map)['creationDate'] as Timestamp? ?? Timestamp.now()).compareTo((a.data() as Map)['creationDate'] as Timestamp? ?? Timestamp.now()));
        return _buildGrid(filtered, true);
      },
    );
  }

  Widget _buildIndexSubView(String targetUserId) {
    Stream<QuerySnapshot> stream = _indexSubTabIndex == 0
        ? context.read<UserRepository>().watchUserWorks(targetUserId)
        : context.read<UserRepository>().watchUserMentions(targetUserId);
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        return _buildGrid(snapshot.data!.docs, false);
      },
    );
  }

  Widget _buildSettingsSubView(String targetUserId) {
    if (_settingsSubTabIndex == 0) {
      // Global Shortcodes
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("GLOBAL APP SHORTCODES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 24),
              TextField(controller: _loginZineController, decoration: const InputDecoration(labelText: 'Login Zine ShortCode', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 16),
              TextField(controller: _registerZineController, decoration: const InputDecoration(labelText: 'Register Zine ShortCode', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 24),
              ElevatedButton(
                  onPressed: _saveGlobalShortcodes,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text("SAVE CONFIGURATION", style: TextStyle(fontWeight: FontWeight.bold))
              ),
            ],
          ),
        ),
      );
    } else if (_settingsSubTabIndex == 1) {
      // Managed Profiles
      return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('Users').where('isManaged', isEqualTo: true).where('managers', arrayContains: targetUserId).snapshots(),
          builder: (context, snapshot) {
            final List<Widget> buttons = [_QuickActionTile(label: "+ managed profile", color: Colors.indigo, onTap: _showCreateManagedProfileDialog)];
            if (!snapshot.hasData) {
              return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
            }
            final docs = snapshot.data!.docs;
            return SliverPadding(
              padding: const EdgeInsets.all(8.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index < buttons.length) {
                    return buttons[index];
                  }
                  return _MakerItemTile(doc: docs[index - buttons.length], shouldEdit: true);
                }, childCount: docs.length + buttons.length),
              ),
            );
          }
      );
    } else {
      // Permissions
      return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('Users').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
            }
            final docs = snapshot.data!.docs;
            return SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final uid = docs[index].id;
                  final role = data['role'] ?? 'user';
                  final username = data['username'] ?? 'unknown';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                    child: ListTile(
                      title: Text("@$username", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text("UID: $uid", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      trailing: DropdownButton<String>(
                        value: ['admin', 'moderator', 'curator', 'user'].contains(role) ? role : 'user',
                        underline: const SizedBox(),
                        items: ['admin', 'moderator', 'curator', 'user'].map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))).toList(),
                        onChanged: (newRole) async {
                          if (newRole == null) {
                            return;
                          }
                          await FirebaseFirestore.instance.collection('Users').doc(uid).update({
                            'role': newRole,
                            'isCurator': newRole == 'curator' || newRole == 'admin' || newRole == 'moderator',
                          });
                        },
                      ),
                    ),
                  );
                }, childCount: docs.length),
              ),
            );
          }
      );
    }
  }

  Widget _buildGrid(List<dynamic> docs, bool edit) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
        delegate: SliverChildBuilderDelegate((context, index) => _MakerItemTile(doc: docs[index], shouldEdit: edit), childCount: docs.length),
      ),
    );
  }

  Widget _buildEntitiesSubView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').where('status', whereIn: ['draft', 'working']).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        final Map<String, int> entityCounts = {};
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final entities = List<String>.from(data['draftEntities'] ?? []);
          for (var name in entities) {
            entityCounts[name] = (entityCounts[name] ?? 0) + 1;
          }
        }
        if (entityCounts.isEmpty) {
          return const SliverToBoxAdapter(child: Center(child: Text("No entities found.")));
        }
        final sortedNames = entityCounts.keys.toList()..sort((a, b) => entityCounts[b]!.compareTo(entityCounts[a]!));
        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) => _EntityRow(name: sortedNames[index], count: entityCounts[sortedNames[index]]!), childCount: sortedNames.length),
          ),
        );
      },
    );
  }
}

class _UserCommentsView extends StatelessWidget {
  final String userId;
  const _UserCommentsView({required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('artifacts')
          .doc('bqopd')
          .collection('public')
          .doc('data')
          .collection('comments')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No comments found"))));
        }

        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              data['_id'] = docs[index].id;
              return CommentItem(data: data);
            }, childCount: docs.length),
          ),
        );
      },
    );
  }
}

class _MakerCombinedView extends StatelessWidget {
  final String targetUserId;
  final bool showDrafts;

  const _MakerCombinedView({required this.targetUserId, required this.showDrafts});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: FirebaseFirestore.instance.collection('fanzines').snapshots(),
        builder: (context, _) {
          return StreamBuilder(
              stream: FirebaseFirestore.instance.collection('images').snapshots(),
              builder: (context, _) {
                return FutureBuilder<List<dynamic>>(
                    future: _getCombinedData(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
                      }
                      final items = snapshot.data!;

                      if (items.isEmpty) {
                        return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No items found"))));
                      }

                      return SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 5 / 8,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8
                          ),
                          delegate: SliverChildBuilderDelegate((context, index) {
                            return _MakerItemTile(doc: items[index], shouldEdit: true);
                          }, childCount: items.length),
                        ),
                      );
                    }
                );
              }
          );
        }
    );
  }

  Future<List<dynamic>> _getCombinedData() async {
    final fzSnap = await FirebaseFirestore.instance.collection('fanzines').get();
    final imgSnap = await FirebaseFirestore.instance.collection('images').get();

    final List<dynamic> combined = [];

    for (var doc in fzSnap.docs) {
      final data = doc.data();
      if (data['type'] != 'folio' && data['type'] != 'calendar') {
        continue;
      }
      final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
      if (owner != targetUserId) {
        continue;
      }
      final isLive = data['status'] == 'live' || data['status'] == 'published';
      if (showDrafts ? !isLive : isLive) {
        combined.add(doc);
      }
    }

    for (var doc in imgSnap.docs) {
      final data = doc.data();
      if (data['uploaderId'] != targetUserId) {
        continue;
      }
      final isPending = data['status'] == 'pending';
      if (showDrafts ? isPending : !isPending) {
        combined.add(doc);
      }
    }

    combined.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aTime = aData['creationDate'] ?? aData['timestamp'] as Timestamp?;
      final bTime = bData['creationDate'] ?? bData['timestamp'] as Timestamp?;
      return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
    });

    return combined;
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
          if (data['isAlias'] == true) {
            linkText = '/$handle -> /${data['redirect'] ?? 'unknown'}';
          }
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
    String first = name;
    String last = "";
    if (name.contains(' ')) {
      final parts = name.split(' ');
      first = parts.first;
      last = parts.sublist(1).join(' ');
    }
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Editor Widget");
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final target = await showDialog<String>(context: context, builder: (c) {
      final controller = TextEditingController();
      return AlertDialog(title: Text("Create Alias for '$name'"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Enter EXISTING username (target):"), TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")), TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))]);
    });
    if (target == null || target.isEmpty) {
      return;
    }
    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) {
      if (!context.mounted) {
        return;
      }
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

class _MakerItemTile extends StatelessWidget {
  final dynamic doc;
  final bool shouldEdit;

  const _MakerItemTile({required this.doc, this.shouldEdit = false});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final isImage = doc.reference.path.startsWith('images/');
    final title = data['title'] ?? 'Untitled';
    final imageUrl = data['fileUrl'];

    return GestureDetector(
      onTap: () {
        if (isImage) {
          showDialog(
              context: context,
              builder: (_) => ImageViewModal(
                  imageUrl: imageUrl ?? '',
                  imageId: doc.id,
                  imageText: data['text'] ?? data['text_raw']
              )
          );
        } else {
          context.push(shouldEdit ? '/editor/${doc.id}' : '/reader/${doc.id}');
        }
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
                color: Colors.grey[200],
                child: imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : Icon(isImage ? Icons.image : Icons.menu_book, color: Colors.black12, size: 40)
            ),
            Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black54,
                    child: Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis
                    )
                )
            ),
            if (isImage)
              Positioned(
                  top: 4, right: 4,
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      color: Colors.black.withValues(alpha: 0.6),
                      child: const Text("SINGLE", style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold))
                  )
              ),
          ],
        ),
      ),
    );
  }
}