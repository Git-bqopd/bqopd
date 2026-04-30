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
import '../services/user_bootstrap.dart';
import '../services/username_service.dart';
import '../widgets/profile_widget.dart';
import '../widgets/page_wrapper.dart';
import '../widgets/image_upload_modal.dart';
import '../widgets/image_view_modal.dart';
import '../widgets/comment_item.dart';
import '../widgets/reader_panels/social_matrix_tab.dart';

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

    final extra = GoRouterState.of(context).extra;
    final extraMap = extra is Map<String, dynamic> ? extra : null;
    final queryParams = GoRouterState.of(context).uri.queryParameters;

    final initialTab = extraMap?['tab'] as String? ?? queryParams['tab'];
    final initialDrafts = (extraMap?['drafts'] as bool?) ?? (queryParams['drafts'] == 'true');

    return BlocProvider(
      create: (context) => ProfileBloc(
        userRepository: context.read<UserRepository>(),
        engagementRepository: context.read<EngagementRepository>(),
      )..add(LoadProfileRequested(
        userId: targetUserId!,
        currentAuthId: currentUid ?? '',
        isViewerAdmin: userProvider.isAdmin,
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

  bool _canEdit(String uid, bool isManaged, List<String> managers) {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;
    if (uid == currentUid) return true;
    if (isManaged && managers.contains(currentUid)) return true;
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
        onSingleImage: () => _showImageUpload(userId),
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
        'isLive': false,
        'processingStatus': 'complete',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'folio',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
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
        'isLive': false,
        'processingStatus': 'idle',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'ingested',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
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
        'isLive': false,
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
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            _handleCreateManagedProfile();
          }, child: const Text("Create")),
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
          final targetUserId = userData.uid;

          // Generate the exact profile name to search for in entity drafts
          final String profileName = (userData.displayName != null && userData.displayName!.trim().isNotEmpty)
              ? userData.displayName!
              : userData.username;

          final userProvider = context.read<UserProvider>();
          final isOwner = userProvider.currentUserId == targetUserId;
          final canEditProfile = _canEdit(userData.uid, userData.isManaged, userData.managers);

          final bool canSeeDrafts = canEditProfile || userProvider.isAdmin || userProvider.isModerator;

          final activeTab = state.visibleTabs.isEmpty ? 'collection' : state.visibleTabs[state.currentTabIndex];

          return SafeArea(
            child: PageWrapper(
              maxWidth: 800,
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
                          child: Center(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (userProvider.isAdmin) ...[
                                    _buildSubTab("shortcodes", 0, type: 'settings'),
                                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                                  ],
                                  if (isOwner || userProvider.isAdmin) ...[
                                    _buildSubTab("managed profiles", 1, type: 'settings'),
                                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                                  ],
                                  if (userProvider.isAdmin) ...[
                                    _buildSubTab("permissions", 2, type: 'settings'),
                                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                                  ],
                                  if (isOwner)
                                    _buildSubTab("social buttons", 3, type: 'settings'),
                                ],
                              ),
                            ),
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
                                  child: Text(_isUploadingPdf ? "uploading..." : "catalog", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _buildSubTab("curator", 0, type: 'curator'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("publisher", 1, type: 'curator'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("entities", 2, type: 'curator'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("ai training data", 3, type: 'curator'),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (activeTab == 'maker')
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (canEditProfile)
                                GestureDetector(
                                  onTap: () => _showMakerCreateModal(targetUserId),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    decoration: BoxDecoration(border: Border.all(color: Colors.black)),
                                    child: const Text("make", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                                  ),
                                ),
                              if (canEditProfile) const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = false),
                                child: Text("published", style: TextStyle(color: !_showDrafts ? Colors.black : Colors.grey, fontWeight: !_showDrafts ? FontWeight.bold : FontWeight.normal, decoration: !_showDrafts ? TextDecoration.underline : null)),
                              ),
                              if (canSeeDrafts) ...[
                                const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                                GestureDetector(
                                  onTap: () => setState(() => _showDrafts = true),
                                  child: Text("drafts", style: TextStyle(color: _showDrafts ? Colors.black : Colors.grey, fontWeight: _showDrafts ? FontWeight.bold : FontWeight.normal, decoration: _showDrafts ? TextDecoration.underline : null)),
                                ),
                              ],
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
                              _buildSubTab("mentions", 0, type: 'index'),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("comments", 1, type: 'index'),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  _buildContentSliver(targetUserId, isOwner, activeTab, canSeeDrafts, profileName),
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

  Widget _buildContentSliver(String targetUserId, bool isOwner, String activeTab, bool canSeeDrafts, String profileName) {
    switch (activeTab) {
      case 'settings':
        if (_settingsSubTabIndex == 3) {
          return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(24.0), child: SocialMatrixTab())));
        }
        return _buildSettingsSubView(targetUserId);
      case 'curator':
        if (_curatorSubTabIndex == 2) {
          return _buildEntitiesSubView(targetUserId);
        } else if (_curatorSubTabIndex == 3) {
          return _buildAITrainingDataSubView(targetUserId);
        }
        return _buildCuratorSubView(targetUserId, canSeeDrafts);
      case 'maker':
        return _MakerCombinedView(targetUserId: targetUserId, showDrafts: _showDrafts && canSeeDrafts);
      case 'index':
        if (_indexSubTabIndex == 1) {
          return _UserCommentsView(userId: targetUserId);
        }
        return _buildIndexSubView(profileName);
      case 'collection':
        return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Collection Coming Soon"))));
      default:
        return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Coming Soon"))));
    }
  }

  Widget _buildAITrainingDataSubView(String targetUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('images')
          .where('isTrainingData', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(child: Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.grey))));
        }
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }

        final docs = snapshot.data!.docs;
        final List<Map<String, dynamic>> trainingCandidates = [];

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final int correctionScore = data['human_correction_score'] ?? 0;
          final int linkingScore = data['human_linking_score'] ?? 0;

          if (correctionScore > 0 || linkingScore > 0) {
            String displayTitle = data['title'] ?? data['fileName'] ?? 'Untitled';

            final wNum = (data['wholeNumber'] ?? '').toString().trim();
            final iss = (data['issue'] ?? '').toString().trim();
            if (wNum.isNotEmpty) {
              displayTitle = "$displayTitle $wNum";
            } else if (iss.isNotEmpty) {
              displayTitle = "$displayTitle $iss";
            }

            trainingCandidates.add({
              'id': doc.id,
              'title': displayTitle,
              'correctionScore': correctionScore,
              'linkingScore': linkingScore,
              'fileUrl': data['fileUrl'] ?? data['gridUrl'],
              'folioContext': data['folioContext'], // Store this to fetch Fanzine data
            });
          }
        }

        if (trainingCandidates.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48.0),
              child: Center(
                child: Text(
                  "No training data yet.\n\nManually save edits in the CORRECTED TEXT or WIKI-LINK panels in the Reader to generate variance scores.",
                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        trainingCandidates.sort((a, b) {
          final scoreA = (a['correctionScore'] as int) + (a['linkingScore'] as int);
          final scoreB = (b['correctionScore'] as int) + (b['linkingScore'] as int);
          return scoreB.compareTo(scoreA); // Descending
        });

        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = trainingCandidates[index];
              final String? folioContext = item['folioContext'];

              Widget buildCard(String title) {
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                  child: ListTile(
                    leading: item['fileUrl'] != null
                        ? Image.network(item['fileUrl'], width: 40, height: 40, fit: BoxFit.cover)
                        : const Icon(Icons.image),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text("Correction Edits: ${item['correctionScore']} | Link Edits: ${item['linkingScore']}", style: const TextStyle(fontSize: 11)),
                    trailing: OutlinedButton(
                      onPressed: () {
                        // Placeholder for future Diff Viewer
                      },
                      child: const Text("View Details", style: TextStyle(fontSize: 11)),
                    ),
                  ),
                );
              }

              // Fetch the parent Fanzine to display "Title + Whole Number/Issue"
              if (folioContext != null && folioContext.isNotEmpty) {
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('fanzines').doc(folioContext).get(),
                  builder: (context, fzSnap) {
                    String finalTitle = item['title'];

                    if (fzSnap.hasData && fzSnap.data!.exists) {
                      final fzData = fzSnap.data!.data() as Map<String, dynamic>;
                      final fzTitle = fzData['title'] ?? 'Untitled';
                      final wNum = (fzData['wholeNumber'] ?? '').toString().trim();
                      final iss = (fzData['issue'] ?? '').toString().trim();

                      if (wNum.isNotEmpty) {
                        finalTitle = "$fzTitle $wNum";
                      } else if (iss.isNotEmpty) {
                        finalTitle = "$fzTitle $iss";
                      } else {
                        finalTitle = fzTitle;
                      }
                    }

                    return buildCard(finalTitle);
                  },
                );
              }

              return buildCard(item['title']);
            }, childCount: trainingCandidates.length),
          ),
        );
      },
    );
  }

  Widget _buildCuratorSubView(String targetUserId, bool canEdit) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return SliverToBoxAdapter(child: Center(child: Text("Error: ${snap.error}", style: const TextStyle(color: Colors.grey))));
        }
        if (!snap.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        final filtered = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
          final bool isTargetUserItem = (owner == targetUserId || (data['editors'] as List? ?? []).contains(targetUserId));
          if (!isTargetUserItem) return false;

          final hasSource = data.containsKey('sourceFile');
          final isLive = data['isLive'] ?? false;

          if (_curatorSubTabIndex == 0) {
            return hasSource && !isLive;
          }
          return (!hasSource || isLive);
        }).toList();
        filtered.sort((a, b) => ((b.data() as Map)['creationDate'] as Timestamp? ?? Timestamp.now()).compareTo((a.data() as Map)['creationDate'] as Timestamp? ?? Timestamp.now()));
        return _buildGrid(filtered, true, isDraftView: canEdit);
      },
    );
  }

  Widget _buildIndexSubView(String profileName) {
    // Queries the draftEntities array on the Fanzines collection for mentions!
    Stream<QuerySnapshot> stream = FirebaseFirestore.instance
        .collection('fanzines')
        .where('draftEntities', arrayContains: profileName)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Error loading mentions: ${snapshot.error}", style: const TextStyle(fontSize: 10, color: Colors.grey)))));
        }
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No mentions found.", style: TextStyle(color: Colors.grey)))));
        }
        // Force the grid to display only thumbnails for mentions
        return _buildGrid(docs, false, thumbnailOnly: true);
      },
    );
  }

  Widget _buildSettingsSubView(String targetUserId) {
    final userProvider = context.read<UserProvider>();

    if (_settingsSubTabIndex == 0) {
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
              ElevatedButton(onPressed: _saveGlobalShortcodes, style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text("SAVE CONFIGURATION", style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),
      );
    } else if (_settingsSubTabIndex == 1) {
      return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('profiles').where('isManaged', isEqualTo: true).where('managers', arrayContains: targetUserId).snapshots(),
          builder: (context, snapshot) {
            final List<Widget> buttons = [_QuickActionTile(label: "+ managed profile", color: Colors.grey.shade800, onTap: _showCreateManagedProfileDialog)];
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
    } else if (_settingsSubTabIndex == 2) {
      if (!userProvider.isAdmin) {
        return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text("Access restricted to Administrators."))));
      }

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
                  final uid = docs[index].id;
                  final userData = docs[index].data() as Map<String, dynamic>;
                  final dynamic rolesData = userData['roles'];
                  final Set<String> selectedRolesSet = rolesData != null ? Set<String>.from(rolesData) : (userData['role'] != null && userData['role'] != 'user' ? {userData['role']} : <String>{});

                  return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('profiles').doc(uid).get(),
                      builder: (context, profileSnap) {
                        final pData = profileSnap.data?.data() as Map?;
                        final name = pData?['displayName'] ?? pData?['username'] ?? 'unknown';
                        final username = pData?['username'] ?? 'unknown';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                          child: ListTile(
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text("UID: $uid", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(onTap: () => context.go('/$username'), child: Text('/$username', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline))),
                                const SizedBox(width: 16),
                                SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(value: 'admin', label: Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                    ButtonSegment(value: 'moderator', label: Text('MODERATOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                    ButtonSegment(value: 'curator', label: Text('CURATOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                  ],
                                  selected: selectedRolesSet,
                                  onSelectionChanged: (newSelection) async {
                                    if (!context.read<UserProvider>().isAdmin) return;

                                    final rolesList = newSelection.toList();
                                    final bool isCurator = newSelection.contains('curator');
                                    final bool isAdmin = newSelection.contains('admin');
                                    final bool isModerator = newSelection.contains('moderator');

                                    String legacyRole = 'user';
                                    if (isAdmin) {
                                      legacyRole = 'admin';
                                    } else if (isModerator) {
                                      legacyRole = 'moderator';
                                    } else if (isCurator) {
                                      legacyRole = 'curator';
                                    }

                                    final batch = FirebaseFirestore.instance.batch();

                                    batch.update(FirebaseFirestore.instance.collection('Users').doc(uid), {
                                      'roles': rolesList,
                                      'role': legacyRole,
                                      'isCurator': isCurator || isAdmin || isModerator
                                    });

                                    batch.update(FirebaseFirestore.instance.collection('profiles').doc(uid), {
                                      'isCurator': isCurator || isAdmin || isModerator,
                                      'isAdmin': isAdmin
                                    });

                                    await batch.commit();
                                  },
                                  multiSelectionEnabled: true,
                                  emptySelectionAllowed: true,
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                  );
                }, childCount: docs.length),
              ),
            );
          }
      );
    } else {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  Widget _buildGrid(List<dynamic> docs, bool edit, {bool isDraftView = false, bool thumbnailOnly = false}) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
        delegate: SliverChildBuilderDelegate((context, index) => _MakerItemTile(doc: docs[index], shouldEdit: edit, isDraftView: isDraftView, thumbnailOnly: thumbnailOnly), childCount: docs.length),
      ),
    );
  }

  Widget _buildEntitiesSubView(String targetUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(child: Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.grey))));
        }
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        final Map<String, int> entityCounts = {};
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;

          final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
          final bool isTargetUserItem = (owner == targetUserId || (data['editors'] as List? ?? []).contains(targetUserId));
          if (!isTargetUserItem) continue;

          final hasSource = data.containsKey('sourceFile');
          final isLive = data['isLive'] ?? false;

          // Only include entities from fanzines that would appear in the "curator" tab
          if (!hasSource || isLive) continue;

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
      // Removed orderBy to prevent missing index errors and infinite spinners!
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No comments found.", style: TextStyle(color: Colors.grey)))));
        }
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        final docs = snapshot.data!.docs.toList();
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No comments found.", style: TextStyle(color: Colors.grey)))));
        }

        // Sorting the results locally in memory to bypass the requirement for a Firestore Index
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['createdAt'] as Timestamp?;
          final bTime = bData['createdAt'] as Timestamp?;
          return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
        });

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
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
                          delegate: SliverChildBuilderDelegate((context, index) => _MakerItemTile(doc: items[index], shouldEdit: true, isDraftView: showDrafts), childCount: items.length),
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
      final isLive = data['isLive'] ?? false;
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
          statusWidget = InkWell(onTap: () => context.go('/$handle'), child: Text(linkText, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline)));
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
    final messenger = ScaffoldMessenger.of(context);
    String first = name; String last = "";
    if (name.contains(' ')) { final parts = name.split(' '); first = parts.first; last = parts.sublist(1).join(' '); }
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Editor Widget");
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
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
  final bool isDraftView;
  final bool thumbnailOnly;

  const _MakerItemTile({
    required this.doc,
    this.shouldEdit = false,
    this.isDraftView = false,
    this.thumbnailOnly = false,
  });

  bool _is5x8(Map<String, dynamic> data) {
    if (data['is5x8'] == true) {
      return true;
    }
    final w = data['width'] as num?;
    final h = data['height'] as num?;
    if (w != null && h != null) {
      final ratio = w / h;
      return ratio >= 0.58 && ratio <= 0.67;
    }
    return false;
  }

  Future<void> _confirmDelete(BuildContext context, String displayTitle) async {
    final isFanzine = doc.reference.path.startsWith('fanzines/');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete $displayTitle?"),
        content: Text(isFanzine
            ? "Are you sure you want to delete this folio? Direct uploads will be permanently removed. Orphan images imported from your library will be preserved."
            : "Are you sure you want to delete this image? All associated page references will be removed from all folios."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) {
        return;
      }
      if (isFanzine) {
        context.read<ProfileBloc>().add(DeleteFolioRequested(doc.id));
      } else {
        context.read<ProfileBloc>().add(DeleteImageRequested(doc.id));
      }
    }
  }

  Future<String?> _getFolioThumbnail(String fanzineId) async {
    final db = FirebaseFirestore.instance;

    try {
      final coverSnap = await db.collection('fanzines').doc(fanzineId).collection('pages')
          .where('pageNumber', isEqualTo: 1)
          .limit(1)
          .get();

      if (coverSnap.docs.isNotEmpty) {
        final d = coverSnap.docs.first.data();
        final url = d['gridUrl'] ?? d['thumbnailUrl'] ?? d['imageUrl'];
        if (url != null && url.toString().isNotEmpty) return url;
      }

      final pagesSnap = await db.collection('fanzines').doc(fanzineId).collection('pages')
          .where('pageNumber', isGreaterThan: 0)
          .orderBy('pageNumber')
          .limit(1)
          .get();

      if (pagesSnap.docs.isNotEmpty) {
        final pageData = pagesSnap.docs.first.data();
        final url = pageData['gridUrl'] ?? pageData['thumbnailUrl'] ?? pageData['imageUrl'];
        if (url != null && url.toString().isNotEmpty) return url;
      }

      final fallbackPageSnap = await db.collection('fanzines').doc(fanzineId).collection('pages')
          .limit(1)
          .get();

      if (fallbackPageSnap.docs.isNotEmpty) {
        final d = fallbackPageSnap.docs.first.data();
        final url = d['gridUrl'] ?? d['thumbnailUrl'] ?? d['imageUrl'];
        if (url != null && url.toString().isNotEmpty) return url;
      }

      final imagesSnap = await db.collection('images')
          .where('folioContext', isEqualTo: fanzineId)
          .get();

      if (imagesSnap.docs.isNotEmpty) {
        final docs = imagesSnap.docs.toList();
        docs.sort((a, b) {
          final aTime = (a.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final bTime = (b.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        });

        final imgData = docs.first.data();
        return imgData['gridUrl'] ?? imgData['fileUrl'];
      }
    } catch (e) {
      debugPrint("Error fetching folio thumbnail: $e");
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final isFanzine = doc.reference.path.startsWith('fanzines/');
    final title = data['title'] ?? 'Untitled';

    String displayTitle = title;
    if (isFanzine) {
      final wNum = (data['wholeNumber'] ?? '').toString().trim();
      final iss = (data['issue'] ?? '').toString().trim();
      if (wNum.isNotEmpty) {
        displayTitle = "$title $wNum";
      } else if (iss.isNotEmpty) {
        displayTitle = "$title $iss";
      }
    }

    final fileUrl = data['fileUrl'];
    final displayUrl = data['gridUrl'] ?? data['fileUrl'];

    return GestureDetector(
      onTap: () {
        if (!isFanzine) {
          showDialog(context: context, builder: (_) => ImageViewModal(imageUrl: fileUrl ?? '', imageId: doc.id, imageText: data['text'] ?? data['text_raw']));
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
              child: isFanzine
                  ? FutureBuilder<String?>(
                future: _getFolioThumbnail(doc.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                  }
                  if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                    return Image.network(snapshot.data!, fit: BoxFit.cover);
                  }
                  return const Icon(Icons.menu_book, color: Colors.black12, size: 40);
                },
              )
                  : (displayUrl != null
                  ? Image.network(displayUrl, fit: BoxFit.cover)
                  : const Icon(Icons.image, color: Colors.black12, size: 40)),
            ),

            if (!thumbnailOnly) ...[
              Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black54,
                      child: Text(
                          displayTitle,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis
                      )
                  )
              ),

              Positioned(
                top: 26, left: 4, right: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isFanzine)
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('fanzines').doc(doc.id).collection('pages').where('pageNumber', isGreaterThan: 0).snapshots(),
                        builder: (context, snap) {
                          final count = snap.data?.docs.length ?? 0;
                          return _Badge(label: "folio ($count)", color: Colors.grey.shade800);
                        },
                      )
                    else ...[
                      _Badge(label: _is5x8(data) ? "full page 5x8" : "image", color: Colors.grey.shade800),
                      const SizedBox(height: 2),
                      _Badge(label: "${data['width'] ?? '??'}x${data['height'] ?? '??'}", color: Colors.black, opacity: 0.7),
                    ],
                  ],
                ),
              ),
            ],

            if (isDraftView && !thumbnailOnly)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => _confirmDelete(context, displayTitle),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final double opacity;
  const _Badge({required this.label, required this.color, this.opacity = 0.8});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: opacity), borderRadius: BorderRadius.circular(4)),
      child: Text(
          label.toLowerCase(),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.normal),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis
      ),
    );
  }
}