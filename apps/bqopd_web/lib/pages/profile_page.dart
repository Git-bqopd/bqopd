import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/web_utils.dart';

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

  const ProfilePage({
    required this.authState,
    required this.authBloc,
    required this.userRepository,
    required this.engagementRepository,
    this.userId,
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

  int _settingsSubTabIndex = 0;

  String get _targetUid => component.userId ?? component.authState?.user?.uid ?? '';
  bool get _isMe => component.authState?.user?.uid != null && component.authState?.user?.uid == _targetUid;

  @override
  void initState() {
    super.initState();

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
        final initialTab = decoded['mainTab'] as String?;
        _settingsSubTabIndex = decoded['settingsSubTab'] as int? ?? 0;
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
          Router.of(context).replace('/${profile.username}');
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

    String? initialTab;
    try {
      final cached = getLocalPreference('profile_sticky_prefs_$_targetUid');
      if (cached != null) {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        initialTab = decoded['mainTab'] as String?;
        _settingsSubTabIndex = decoded['settingsSubTab'] as int? ?? 0;
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

          _profileBloc?.add(LoadProfileRequested(
            userId: _targetUid,
            currentAuthId: uid,
            isViewerAdmin: isViewerAdmin,
            isViewerModerator: isViewerModerator,
            isViewerCurator: isViewerCurator,
          ));
        }
      });
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
      'settingsSubTab': _settingsSubTabIndex,
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
        );
      case 'index':
        return ProfileIndexTab(
          targetUserId: _targetUid,
          profileName: _blocState.userData?.displayName ?? _blocState.userData?.username ?? '',
          userRepository: component.userRepository,
        );
      case 'settings':
        return ProfileSettingsTab(
          targetUserId: _targetUid,
          isMe: _isMe,
          viewerAccount: _viewerAccount,
          userRepository: component.userRepository,
          initialSubTab: _settingsSubTabIndex,
          onSubTabChanged: (val) {
            setState(() {
              _settingsSubTabIndex = val;
            });
            _savePrefs();
          },
        );
      case 'curator':
        return ProfileCuratorTab(
          targetUserId: _targetUid,
          userRepository: component.userRepository,
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
            if (state.visibleTabs.isNotEmpty)
              div(
                [
                  for (int i = 0; i < state.visibleTabs.length; i++) ...[
                    _buildMainNavigationTab(state.visibleTabs[i], i),
                    if (i < state.visibleTabs.length - 1)
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
            if (state.visibleTabs.isNotEmpty)
              _buildContentBody(state.visibleTabs[state.currentTabIndex])
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