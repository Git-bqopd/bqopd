import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';

// Decoupled sub-tab widgets
import '../components/profile/profile_card.dart';
import '../components/profile/maker_tab.dart';
import '../components/profile/index_tab.dart';
import '../components/profile/settings_tab.dart';
import '../components/profile/curator_tab.dart';

/// Clean coordinator page tracking target profiles using core's ProfileBloc.
/// Implements state management, viewer authentication, and tab navigation.
class ProfilePage extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc authBloc;
  final IUserRepository userRepository;
  final IEngagementRepository engagementRepository;
  final String? userId; // Optional override for specific profiles
  final String? initialTab;
  final String? initialSubTab;

  const ProfilePage({
    required this.authState,
    required this.authBloc,
    required this.userRepository,
    required this.engagementRepository,
    this.userId,
    this.initialTab,
    this.initialSubTab,
    super.key,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ProfileBloc? _profileBloc;
  StreamSubscription<ProfileState>? _blocSub;
  ProfileState _blocState = const ProfileState(isLoading: true);

  // Viewer context metadata
  UserAccount? _viewerAccount;
  StreamSubscription? _viewerAccountSub;
  StreamSubscription? _viewerRedirectSub;

  // Subscriptions for counting target user's public content
  StreamSubscription? _rawWorksSub;
  FirebaseSubscription? _rawImagesSub;
  StreamSubscription? _rawMentionsSub;
  FirebaseSubscription? _rawCommentsSub;

  List<Map<String, dynamic>> _userWorks = [];
  int _publicWorksCount = 0;
  int _publicImagesCount = 0;
  int _publicMentionsCount = 0;
  int _publicCommentsCount = 0;

  String? _activeSubTabName;

  String get _targetUid => component.userId ?? component.authState?.user?.uid ?? '';
  bool get _isMe => component.authState?.user?.uid != null && component.authState?.user?.uid == _targetUid;

  @override
  void initState() {
    super.initState();
    _activeSubTabName = component.initialSubTab;

    // SERVER PRE-RENDERING GUARD: Only initialize dynamic streams on the client
    if (kIsWeb) {
      _loadCachedStickyPrefs();
      Future.microtask(() {
        if (mounted) {
          _initDataPipeline();
        }
      });
    }
  }

  @override
  void didUpdateComponent(ProfilePage oldComponent) {
    super.didUpdateComponent(oldComponent);
    final String oldTarget = oldComponent.userId ?? oldComponent.authState?.user?.uid ?? '';
    final String currentTarget = _targetUid;

    if (oldComponent.initialSubTab != component.initialSubTab) {
      _activeSubTabName = component.initialSubTab;
    }

    // Reactively update BLoC active tab when URL route parameters change
    if (oldComponent.initialTab != component.initialTab && component.initialTab != null) {
      final tabs = _blocState.visibleTabs;
      if (tabs.contains(component.initialTab)) {
        final newIndex = tabs.indexOf(component.initialTab!);
        if (newIndex != _blocState.currentTabIndex) {
          _profileBloc?.add(ChangeTabRequested(newIndex));
        }
      }
    }

    if (oldTarget != currentTarget || oldComponent.authState?.user?.uid != component.authState?.user?.uid) {
      _cleanupDataPipeline();
      if (kIsWeb) {
        Future.microtask(() {
          if (mounted) {
            _initDataPipeline();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _cleanupDataPipeline();
    _viewerAccountSub?.cancel();
    _viewerRedirectSub?.cancel();
    super.dispose();
  }

  void _loadCachedStickyPrefs() {
    try {
      final cached = getLocalPreference('profile_sticky_prefs_$_targetUid');
      if (cached != null) {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        final initialTab = component.initialTab ?? decoded['mainTab'] as String?;
        if (initialTab != null) {
          setState(() {
            _blocState = _blocState.copyWith(visibleTabs: [initialTab]);
          });
        }
      }
    } catch (_) {}
  }

  void _initDataPipeline() {
    _profileBloc = ProfileBloc(
      userRepository: component.userRepository,
      engagementRepository: component.engagementRepository,
    );

    final currentUid = component.authState?.user?.uid;
    final bool isViewerAdmin = _viewerAccount?.role == 'admin' || (_viewerAccount?.roles.contains('admin') ?? false);
    final bool isViewerModerator = _viewerAccount?.role == 'moderator' || (_viewerAccount?.roles.contains('moderator') ?? false);
    final bool isViewerCurator = _viewerAccount?.role == 'curator' || (_viewerAccount?.roles.contains('curator') ?? false) || (_viewerAccount?.isCurator ?? false);

    // CLIENT REDIRECTION: If viewing my own profile without a vanity URL, resolve and redirect
    if (component.userId == null && currentUid != null) {
      _viewerRedirectSub = component.userRepository.watchUser(currentUid).listen((profile) {
        if (profile != null && profile.username.isNotEmpty && mounted) {
          Router.of(context).replace('/@${profile.username}');
        }
      });
      return;
    }

    if (_targetUid.isEmpty) {
      setState(() {
        _blocState = const ProfileState(
          isLoading: false,
          errorMessage: "Authentication required to view this profile.",
        );
      });
      return;
    }

    _blocSub = _profileBloc!.stream.listen((state) {
      if (mounted) {
        setState(() {
          _blocState = state;
        });
      }
    });

    String? initialTab = component.initialTab;
    try {
      if (initialTab == null) {
        final cached = getLocalPreference('profile_sticky_prefs_$_targetUid');
        if (cached != null) {
          final decoded = jsonDecode(cached) as Map<String, dynamic>;
          initialTab = decoded['mainTab'] as String?;
        }
      }
    } catch (_) {}

    _profileBloc!.add(LoadProfileRequested(
      userId: _targetUid,
      currentAuthId: currentUid ?? '',
      isViewerAdmin: isViewerAdmin,
      isViewerModerator: isViewerModerator,
      isViewerCurator: isViewerCurator,
      initialTab: initialTab,
    ));

    _listenToViewerAccount();

    // Setup public metric monitors to reactively filter tabs on someone else's profile
    if (!_isMe) {
      _rawWorksSub = component.userRepository.watchUserWorks(_targetUid).listen((works) {
        if (mounted) {
          setState(() {
            _userWorks = works;
            _publicWorksCount = works.where((w) => w['isLive'] == true).length;
          });
        }
      });

      _rawImagesSub = fsListenQuery('images', 'uploaderId', '==', jsonEncode(_targetUid), '', false, (jsonStr) {
        try {
          final List decoded = jsonDecode(jsonStr);
          int approvedCount = 0;
          for (var d in decoded) {
            final data = d['data'] as Map<String, dynamic>? ?? {};
            if (data['status'] == 'approved' || data['status'] != 'pending') {
              approvedCount++;
            }
          }
          if (mounted) {
            setState(() {
              _publicImagesCount = approvedCount;
            });
          }
        } catch (_) {}
      });

      _rawMentionsSub = component.userRepository.watchUserMentions(_targetUid).listen((mentions) {
        if (mounted) {
          setState(() {
            _publicMentionsCount = mentions.length;
          });
        }
      });

      _rawCommentsSub = fsListenQuery('artifacts/bqopd/public/data/comments', 'userId', '==', jsonEncode(_targetUid), '', false, (jsonStr) {
        try {
          final List decoded = jsonDecode(jsonStr);
          if (mounted) {
            setState(() {
              _publicCommentsCount = decoded.length;
            });
          }
        } catch (_) {}
      });
    }
  }

  void _cleanupDataPipeline() {
    _blocSub?.cancel();
    _blocSub = null;
    _profileBloc?.close();
    _profileBloc = null;
    _viewerAccountSub?.cancel();
    _viewerAccountSub = null;
    _viewerRedirectSub?.cancel();
    _viewerRedirectSub = null;

    _rawWorksSub?.cancel();
    _rawWorksSub = null;
    _rawImagesSub?.callAsFunction();
    _rawImagesSub = null;
    _rawMentionsSub?.cancel();
    _rawMentionsSub = null;
    _rawCommentsSub?.callAsFunction();
    _rawCommentsSub = null;
  }

  void _listenToViewerAccount() {
    _viewerAccountSub?.cancel();
    _viewerAccountSub = null;

    final uid = component.authState?.user?.uid;
    if (uid != null) {
      _viewerAccountSub = component.userRepository.watchUserAccount(uid).listen((account) {
        if (account != null && mounted) {
          setState(() {
            _viewerAccount = account;
          });

          final isViewerAdmin = account.role == 'admin' || account.roles.contains('admin');
          final isViewerModerator = account.role == 'moderator' || account.roles.contains('moderator');
          final isViewerCurator = account.role == 'curator' || account.roles.contains('curator') || account.isCurator;

          // Preserve active tab state during viewer account stream emissions
          String? activeTab;
          if (_blocState.visibleTabs.isNotEmpty && _blocState.currentTabIndex < _blocState.visibleTabs.length) {
            activeTab = _blocState.visibleTabs[_blocState.currentTabIndex];
          } else {
            activeTab = component.initialTab;
          }

          _profileBloc?.add(LoadProfileRequested(
            userId: _targetUid,
            currentAuthId: uid,
            isViewerAdmin: isViewerAdmin,
            isViewerModerator: isViewerModerator,
            isViewerCurator: isViewerCurator,
            initialTab: activeTab,
          ));
        }
      });
    }
  }

  void _updateProfileUrl({String? mainTab, String? subTab}) {
    final username = _blocState.userData?.username;
    if (username == null || username.isEmpty) return;

    final String tab = mainTab ??
        (_blocState.visibleTabs.isNotEmpty && _blocState.currentTabIndex < _blocState.visibleTabs.length
            ? _blocState.visibleTabs[_blocState.currentTabIndex]
            : '');
    if (tab.isEmpty) return;

    String path = '/@$username/$tab';
    if (subTab != null && subTab.isNotEmpty) {
      path += '/$subTab';
    }

    if (kIsWeb) {
      try {
        Router.of(context).replace(path);
      } catch (_) {}
    }
  }

  void _savePrefs() {
    if (!_isMe) return;
    final uid = component.authState?.user?.uid;
    if (uid == null) return;

    String mainTab = '';
    try {
      if (_blocState.visibleTabs.isNotEmpty) {
        mainTab = _blocState.visibleTabs[_blocState.currentTabIndex];
      }
    } catch (_) {}

    if (mainTab.isEmpty) return;

    final prefsData = {
      'mainTab': mainTab,
      'settingsSubTab': _activeSubTabName ?? '',
    };

    try {
      saveLocalPreference('profile_sticky_prefs_$uid', jsonEncode(prefsData));
    } catch (_) {}

    fsUpdateDoc('Users/$uid', jsonEncode({
      'preferences.profile': prefsData,
    })).catchError((_) {
      fsSetDoc('Users/$uid', jsonEncode({
        'preferences': {'profile': prefsData}
      }), true);
    });
  }

  Component _buildMainNavigationTab(String name, int index) {
    final bool isActive = _blocState.currentTabIndex == index;
    return span(
      [text(name.toLowerCase())],
      classes: isActive ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
      events: {
        'click': (e) {
          _profileBloc?.add(ChangeTabRequested(index));
          if (index < _blocState.visibleTabs.length) {
            final newTab = _blocState.visibleTabs[index];
            _activeSubTabName = null; // Reset subtab when changing main tab
            _updateProfileUrl(mainTab: newTab);
            _savePrefs();
          }
        }
      },
    );
  }

  Component _buildContentBody(String tabName) {
    switch (tabName) {
      case 'maker':
        return ProfileMakerTab(
          targetUserId: _targetUid,
          isMe: _isMe,
          canSeeDrafts: _isMe || (_viewerAccount?.role == 'admin' || (_viewerAccount?.roles.contains('admin') ?? false)) || (_viewerAccount?.role == 'moderator' || (_viewerAccount?.roles.contains('moderator') ?? false)) || (_viewerAccount?.role == 'curator' || (_viewerAccount?.roles.contains('curator') ?? false) || (_viewerAccount?.isCurator ?? false)),
          userRepository: component.userRepository,
          authState: component.authState,
          initialSubTab: _activeSubTabName,
          onSubTabChanged: (subTabName) {
            _activeSubTabName = subTabName;
            _updateProfileUrl(mainTab: 'maker', subTab: subTabName);
            _savePrefs();
          },
        );
      case 'index':
        return ProfileIndexTab(
          targetUserId: _targetUid,
          profileName: _blocState.userData?.displayName ?? _blocState.userData?.username ?? '',
          userRepository: component.userRepository,
          initialSubTab: _activeSubTabName,
          onSubTabChanged: (subTabName) {
            _activeSubTabName = subTabName;
            _updateProfileUrl(mainTab: 'index', subTab: subTabName);
            _savePrefs();
          },
        );
      case 'settings':
        return ProfileSettingsTab(
          targetUserId: _targetUid,
          isMe: _isMe,
          viewerAccount: _viewerAccount,
          userRepository: component.userRepository,
          initialSubTabName: _activeSubTabName,
          onSubTabChangedName: (subTabName) {
            _activeSubTabName = subTabName;
            _updateProfileUrl(mainTab: 'settings', subTab: subTabName);
            _savePrefs();
          },
        );
      case 'curator':
        return ProfileCuratorTab(
          targetUserId: _targetUid,
          userRepository: component.userRepository,
          initialSubTab: _activeSubTabName,
          onSubTabChanged: (subTabName) {
            _activeSubTabName = subTabName;
            _updateProfileUrl(mainTab: 'curator', subTab: subTabName);
            _savePrefs();
          },
        );
      case 'collection':
      default:
        return div(
          [
            span([text('analytics')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 56px;'}),
            h3([text('${tabName.toUpperCase()} coming soon')], classes: 'font-bold text-black text-lg mt-4'),
            p([text('Archival features are currently being generated on our backend.')], classes: 'text-sm text-gray mt-2')
          ],
          classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
        );
    }
  }

  @override
  Component build(BuildContext context) {
    final state = _blocState;

    if (state.isLoading) {
      return div(
        [p([text('Loading profile...')])],
        classes: 'flex-col items-center justify-center w-full',
        attributes: const {'style': 'min-height: 100vh;'},
      );
    }

    if (state.errorMessage != null) {
      return div(
        [p([text(state.errorMessage!)], classes: 'error-msg')],
        classes: 'flex-col items-center justify-center w-full',
        attributes: const {'style': 'min-height: 100vh;'},
      );
    }

    final userData = state.userData!;

    // Dynamic Hiding Filter logic
    final List<String> originalTabs = state.visibleTabs;
    final List<String> filteredTabs = [];

    for (var tab in originalTabs) {
      if (_isMe) {
        // Profile owners see every tab regardless of contents
        filteredTabs.add(tab);
      } else {
        // Guest/Viewer constraints: Hide empty workspaces
        if (tab == 'collection') {
          continue; // Always hide the placeholder collection tab for guests
        }
        if (tab == 'maker') {
          if (_publicWorksCount > 0 || _publicImagesCount > 0) {
            filteredTabs.add(tab);
          }
          continue;
        }
        if (tab == 'index') {
          if (_publicMentionsCount > 0 || _publicCommentsCount > 0) {
            filteredTabs.add(tab);
          }
          continue;
        }
        if (tab == 'curator') {
          final draftsCount = _userWorks.where((w) => w['isLive'] != true).length;
          if (draftsCount > 0) {
            filteredTabs.add(tab);
          }
          continue;
        }
        filteredTabs.add(tab);
      }
    }

    String activeTabName = '';
    if (state.currentTabIndex < originalTabs.length) {
      activeTabName = originalTabs[state.currentTabIndex];
    }

    int resolvedTabIndex = filteredTabs.indexOf(activeTabName);
    if (resolvedTabIndex == -1) {
      resolvedTabIndex = 0;
    }

    return div(
      [
        div(
          [
            // 1. Profile metadata envelope card
            ProfileCard(
              profile: userData,
              isMe: _isMe,
              isFollowing: state.isFollowing,
              onFollowToggle: () {
                _profileBloc?.add(ToggleFollowRequested());
              },
            ),

            div([], classes: 'profile-spacer'),

            // 2. Tab selection bar
            if (filteredTabs.isNotEmpty)
              div(
                [
                  for (int i = 0; i < filteredTabs.length; i++) ...[
                    _buildMainNavigationTab(filteredTabs[i], originalTabs.indexOf(filteredTabs[i])),
                    if (i < filteredTabs.length - 1)
                      span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
                  ]
                ],
                classes: 'bg-white rounded-md shadow-sm py-4',
                attributes: const {
                  'style': 'display: flex; justify-content: center; align-items: center; overflow-x: auto; box-sizing: border-box; width: 100%;'
                },
              ),

            div([], classes: 'profile-spacer'),

            // 3. Main content tab view
            if (filteredTabs.isNotEmpty)
              _buildContentBody(filteredTabs[resolvedTabIndex])
          ],
          classes: 'unified-profile-column',
        )
      ],
      attributes: const {
        'style': 'min-height: 100vh; background-color: #e5e5e5; display: flex; flex-direction: column; align-items: center; justify-content: flex-start; padding-top: 16px; padding-bottom: 80px; box-sizing: border-box;'
      },
    );
  }
}