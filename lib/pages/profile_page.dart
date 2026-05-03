import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../blocs/profile/profile_bloc.dart';
import '../repositories/user_repository.dart';
import '../repositories/engagement_repository.dart';
import '../services/user_provider.dart';
import '../models/user_profile.dart';

import '../widgets/profile_widget.dart';
import '../widgets/page_wrapper.dart';
import '../widgets/image_upload_modal.dart';

// Extracted Modular Components
import '../widgets/profile/tabs/profile_settings_tab.dart';
import '../widgets/profile/tabs/profile_curator_tab.dart';
import '../widgets/profile/tabs/profile_maker_tab.dart';
import '../widgets/profile/tabs/profile_index_tab.dart';
import '../widgets/profile/utils/profile_tabs_delegate.dart';
import '../widgets/profile/utils/create_managed_profile_dialog.dart';
import '../widgets/profile/utils/profile_creation_utils.dart';

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

    final isMe = targetUserId == currentUid;
    final prefs = userProvider.userAccount?.preferences['profile'] as Map<String, dynamic>? ?? {};

    String? explicitTab = extraMap?['tab'] as String? ?? queryParams['tab'];
    String? explicitSub = extraMap?['sub'] as String? ?? queryParams['sub'];
    bool? explicitDrafts = (extraMap?['drafts'] as bool?) ?? (queryParams['drafts'] == 'true' ? true : null);

    String? initialTab = explicitTab;
    bool initialDrafts = false;

    if (isMe) {
      initialTab ??= prefs['mainTab'] as String?;
      initialDrafts = explicitDrafts ?? (prefs['showDrafts'] as bool? ?? false);
    } else {
      initialTab ??= 'maker';
      initialDrafts = explicitDrafts ?? false;
    }

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
      child: _ProfilePageView(
        initialDrafts: initialDrafts,
        isMe: isMe,
        prefs: prefs,
        explicitSub: explicitSub,
      ),
    );
  }
}

class _ProfilePageView extends StatefulWidget {
  final bool initialDrafts;
  final bool isMe;
  final Map<String, dynamic> prefs;
  final String? explicitSub;

  const _ProfilePageView({
    this.initialDrafts = false,
    required this.isMe,
    required this.prefs,
    this.explicitSub,
  });

  @override
  State<_ProfilePageView> createState() => _ProfilePageViewState();
}

class _ProfilePageViewState extends State<_ProfilePageView> {
  int _makerSubTabIndex = 0;
  int _curatorSubTabIndex = 0;
  int _indexSubTabIndex = 0;
  int _settingsSubTabIndex = 0;
  bool _isUploadingPdf = false;

  final _loginZineController = TextEditingController();
  final _registerZineController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _makerSubTabIndex = widget.initialDrafts ? 1 : 0;

    if (widget.explicitSub == 'hashtags') {
      _indexSubTabIndex = 0;
    } else if (widget.explicitSub == 'mentions') {
      _indexSubTabIndex = 1;
    } else if (widget.explicitSub == 'comments') {
      _indexSubTabIndex = 2;
    } else if (widget.isMe) {
      _curatorSubTabIndex = widget.prefs['curatorSubTab'] as int? ?? 0;
      _indexSubTabIndex = widget.prefs['indexSubTab'] as int? ?? 0;
      _settingsSubTabIndex = widget.prefs['settingsSubTab'] as int? ?? 0;
    }

    _loadGlobalSettings();
  }

  @override
  void didUpdateWidget(covariant _ProfilePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.explicitSub != oldWidget.explicitSub && widget.explicitSub != null) {
      setState(() {
        if (widget.explicitSub == 'hashtags') _indexSubTabIndex = 0;
        if (widget.explicitSub == 'mentions') _indexSubTabIndex = 1;
        if (widget.explicitSub == 'comments') _indexSubTabIndex = 2;
      });
    }
  }

  @override
  void dispose() {
    _loginZineController.dispose();
    _registerZineController.dispose();
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved successfully!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  void _savePrefs({String? newMainTab}) {
    if (!widget.isMe) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    String mainTab = newMainTab ?? '';
    if (mainTab.isEmpty) {
      try {
        final profileState = context.read<ProfileBloc>().state;
        if (profileState.visibleTabs.isNotEmpty) {
          mainTab = profileState.visibleTabs[profileState.currentTabIndex];
        }
      } catch (_) {}
    }
    if (mainTab.isEmpty) return;

    FirebaseFirestore.instance.collection('Users').doc(uid).set({
      'preferences': {
        'profile': {
          'mainTab': mainTab,
          'showDrafts': _makerSubTabIndex == 1,
          'curatorSubTab': _curatorSubTabIndex,
          'indexSubTab': _indexSubTabIndex,
          'settingsSubTab': _settingsSubTabIndex,
        }
      }
    }, SetOptions(merge: true));
  }

  void _updateUrlIfNeeded(String username) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final currentUri = GoRouterState.of(context).uri;
        if (currentUri.path != '/$username' && currentUri.path != '/profile') {
          context.replace('/$username${currentUri.hasQuery ? '?${currentUri.query}' : ''}');
        }
      } catch (_) {}
    });
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
        onCreateFolio: () => ProfileCreationUtils.createFolio(context, userId, isSingleImage: false),
        onCreateCalendar: () => ProfileCreationUtils.createCalendarFanzine(context, userId),
        onCreateArticle: () => ProfileCreationUtils.createArticleFanzine(context, userId),
      ),
    );
  }

  void _showCatalogModal(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogModal(
        onUploadPdf: () => ProfileCreationUtils.handlePdfUpload(context, userId, (val) => setState(() => _isUploadingPdf = val)),
        onUploadImages: () => ProfileCreationUtils.createArchivalFanzine(context, userId),
      ),
    );
  }

  void _showCreateManagedProfileDialog() {
    showDialog(context: context, builder: (_) => const CreateManagedProfileDialog());
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
          if (state.userData != null) _updateUrlIfNeeded(state.userData!.username);
        },
        builder: (context, state) {
          if (state.isLoading) return const Center(child: CircularProgressIndicator());
          if (state.userData == null) return const Center(child: Text("Profile not found."));

          final userData = state.userData!;
          final targetUserId = userData.uid;
          final userProvider = context.read<UserProvider>();
          final isOwner = userProvider.currentUserId == targetUserId;
          final canEditProfile = _canEdit(userData.uid, userData.isManaged, userData.managers);
          final bool canSeeDrafts = canEditProfile || userProvider.isAdmin || userProvider.isModerator;

          int currentIndex = state.currentTabIndex;
          if (currentIndex >= state.visibleTabs.length) currentIndex = 0;

          final activeTab = state.visibleTabs.isEmpty ? 'collection' : state.visibleTabs[currentIndex];
          final bool showAsHashtag = activeTab == 'index' && _indexSubTabIndex == 0;

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
                        showAsHashtag: showAsHashtag,
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: ProfileTabsDelegate(
                      child: SizedBox(
                        height: 50,
                        child: ProfileNavBar(
                          tabTitles: state.visibleTabs,
                          currentIndex: currentIndex,
                          onTabChanged: (idx) {
                            context.read<ProfileBloc>().add(ChangeTabRequested(idx));
                            if (!widget.isMe) {
                              setState(() {
                                _makerSubTabIndex = 0;
                                _curatorSubTabIndex = 0;
                                _indexSubTabIndex = userData.isManaged ? 1 : 0;
                                _settingsSubTabIndex = 0;
                              });
                            }
                            if (idx < state.visibleTabs.length) _savePrefs(newMainTab: state.visibleTabs[idx]);
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
                      delegate: ProfileTabsDelegate(
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
                      delegate: ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isOwner)
                                GestureDetector(
                                  onTap: () => _showCatalogModal(targetUserId),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    decoration: BoxDecoration(border: Border.all(color: Colors.black)),
                                    child: Text(_isUploadingPdf ? "uploading..." : "catalog", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                                  ),
                                ),
                              if (isOwner) const SizedBox(width: 12),
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
                      delegate: ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isOwner)
                                GestureDetector(
                                  onTap: () => _showMakerCreateModal(targetUserId),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    decoration: BoxDecoration(border: Border.all(color: Colors.black)),
                                    child: const Text("make", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                                  ),
                                ),
                              if (isOwner) const SizedBox(width: 12),
                              _buildSubTab("published", 0, type: 'maker'),
                              if (canSeeDrafts) ...[
                                const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                                _buildSubTab("drafts", 1, type: 'maker'),
                              ],
                              if (userProvider.isModerator && isOwner) ...[
                                const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                                _buildSubTab("moderator", 2, type: 'maker'),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (activeTab == 'index')
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!userData.isManaged) ...[
                                _buildSubTab("#hashtags", 0, type: 'index'),
                                const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              ],
                              _buildSubTab("mentions", 1, type: 'index'),
                              if (!userData.isManaged) ...[
                                const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                                _buildSubTab("comments", 2, type: 'index'),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                  ..._buildContentSlivers(targetUserId, activeTab, canSeeDrafts, userData),
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
    } else if (type == 'maker') {
      currentIdx = _makerSubTabIndex;
    } else {
      currentIdx = _settingsSubTabIndex;
    }

    final isActive = currentIdx == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (type == 'curator') _curatorSubTabIndex = index;
          else if (type == 'index') _indexSubTabIndex = index;
          else if (type == 'maker') _makerSubTabIndex = index;
          else _settingsSubTabIndex = index;
        });
        _savePrefs();
      },
      child: Text(
          label,
          style: TextStyle(
              color: isActive ? Colors.black : Colors.grey,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              decoration: isActive ? TextDecoration.underline : null
          )
      ),
    );
  }

  List<Widget> _buildContentSlivers(String targetUserId, String activeTab, bool canSeeDrafts, UserProfile userData) {
    final String profileName = userData.displayName.trim().isNotEmpty ? userData.displayName : userData.username;

    switch (activeTab) {
      case 'settings':
        return [ProfileSettingsTab(
          subTabIndex: _settingsSubTabIndex,
          targetUserId: targetUserId,
          loginZineController: _loginZineController,
          registerZineController: _registerZineController,
          onSaveGlobalShortcodes: _saveGlobalShortcodes,
          onShowCreateManagedProfileDialog: _showCreateManagedProfileDialog,
        )];
      case 'curator':
        return [ProfileCuratorTab(
          subTabIndex: _curatorSubTabIndex,
          targetUserId: targetUserId,
          canEdit: canSeeDrafts,
        )];
      case 'maker':
        return [ProfileMakerTab(
          subTabIndex: _makerSubTabIndex,
          targetUserId: targetUserId,
          canSeeDrafts: canSeeDrafts,
        )];
      case 'index':
        return [ProfileIndexTab(
          subTabIndex: _indexSubTabIndex,
          userData: userData,
          profileName: profileName,
        )];
      case 'collection':
        return [const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Collection Coming Soon"))))];
      default:
        return [const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Coming Soon"))))];
    }
  }
}