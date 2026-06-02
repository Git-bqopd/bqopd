import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/firebase_mocks.dart';
import '../utils/web_utils.dart';

// Decoupled Sub-View Components
import '../components/profile/profile_card.dart';
import '../components/profile/maker_tab.dart';
import '../components/profile/index_tab.dart';
import '../components/profile/settings_tab.dart';
import '../components/profile/curator_tab.dart';

/// Clean coordinator page tracking live database stream sessions,
/// layout boundaries, and sticky history restorations.
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
  UserProfile? _profileData;
  UserAccount? _viewerAccount;
  bool _isLoading = true;
  bool _isFollowing = false;
  int _currentTabIndex = 0;
  List<String> _visibleTabs = [];
  String? _errorMessage;

  // Sub-tab selection caches
  int _settingsSubTabIndex = 0;
  int _curatorSubTabIndex = 0;
  int _indexSubTabIndex = 0;
  bool _showDrafts = false;

  // Sticky Tab Recovery Buffer
  String? _tempSavedMainTab;

  // Stream Subscriptions
  StreamSubscription? _profileSub;
  StreamSubscription? _followSub;
  StreamSubscription? _viewerAccountSub;
  StreamSubscription? _viewerProfileSub;

  // Local data lists
  List<Map<String, dynamic>> _userWorks = [];
  List<Map<String, dynamic>> _userMentions = [];
  List<Map<String, dynamic>> _userComments = [];
  List<Map<String, dynamic>> _allManagedProfiles = [];
  List<Map<String, dynamic>> _allSystemUsers = [];
  List<Map<String, dynamic>> _aiTrainingData = [];

  FirebaseSubscription? _worksSub;
  FirebaseSubscription? _mentionsSub;
  FirebaseSubscription? _commentsSub;
  FirebaseSubscription? _managedSub;
  FirebaseSubscription? _usersSub;
  FirebaseSubscription? _trainingSub;

  String get _targetUid => component.userId ?? component.authState?.user?.uid ?? '';
  bool get _isMe => component.authState?.user?.uid != null && component.authState?.user?.uid == _targetUid;

  @override
  void initState() {
    super.initState();
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
    if (oldComponent.userId != component.userId || oldComponent.authState?.user?.uid != component.authState?.user?.uid) {
      _cancelSubscriptions();
      if (kIsWeb) {
        _initDataPipeline();
      }
    }
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  void _loadCachedStickyPrefs() {
    try {
      final cached = getLocalPreference('profile_sticky_prefs_$_targetUid');
      if (cached != null) {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        _showDrafts = decoded['showDrafts'] as bool? ?? false;
        _curatorSubTabIndex = decoded['curatorSubTab'] as int? ?? 0;
        _indexSubTabIndex = decoded['indexSubTab'] as int? ?? 0;
        _settingsSubTabIndex = decoded['settingsSubTab'] as int? ?? 0;
        _tempSavedMainTab = decoded['mainTab'] as String?;
      }
    } catch (e) {
      print("Error loading local sticky preferences: $e");
    }
  }

  void _cancelSubscriptions() {
    _profileSub?.cancel();
    _followSub?.cancel();
    _viewerAccountSub?.cancel();
    _viewerProfileSub?.cancel();
    _worksSub?.callAsFunction();
    _mentionsSub?.callAsFunction();
    _commentsSub?.callAsFunction();
    _managedSub?.callAsFunction();
    _usersSub?.callAsFunction();
    _trainingSub?.callAsFunction();
  }

  void _initDataPipeline() {
    final currentUid = component.authState?.user?.uid;
    if (component.userId == null && currentUid != null && kIsWeb) {
      _viewerProfileSub = component.userRepository.watchUser(currentUid).listen((profile) {
        if (profile != null && profile.username.isNotEmpty) {
          Router.of(context).replace('/${profile.username}');
        }
      });
      return;
    }

    if (_targetUid.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Please log in to view this profile.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _profileSub = component.userRepository.watchUser(_targetUid).listen((profile) {
      if (profile != null) {
        final bool nameChanged = _profileData?.displayName != profile.displayName;
        setState(() {
          _profileData = profile;
          _rebuildTabSchema();
        });
        if (nameChanged) {
          _setupMentionsPipeline();
        }
      }
    });

    if (!_isMe && currentUid != null) {
      _followSub = component.engagementRepository.isFollowing(_targetUid).listen((following) {
        setState(() {
          _isFollowing = following;
        });
      });
    }

    if (currentUid != null) {
      _viewerAccountSub = component.userRepository.watchUserAccount(currentUid).listen((account) {
        if (account != null) {
          setState(() {
            _viewerAccount = account;
            _rebuildTabSchema();
          });
        }
      });
    }

    _setupWorksPipeline();
    _setupCommentsPipeline();
    _setupManagedProfilesPipeline();
    _setupSystemUsersPipeline();
    _setupTrainingDataPipeline();
  }

  void _rebuildTabSchema() {
    if (_profileData == null) return;
    final bool isViewerAdmin = _viewerAccount?.role == 'admin' || (_viewerAccount?.roles.contains('admin') ?? false);
    final bool isViewerModerator = _viewerAccount?.role == 'moderator' || (_viewerAccount?.roles.contains('moderator') ?? false);
    final bool isViewerCurator = _viewerAccount?.role == 'curator' || (_viewerAccount?.roles.contains('curator') ?? false) || (_viewerAccount?.isCurator ?? false);
    List<String> tabs = [];

    if (_isMe) {
      tabs.add('settings');
    }

    final bool viewerHasAccess = isViewerCurator || isViewerModerator || isViewerAdmin;
    final bool ownerIsCurator = _profileData!.isCurator;
    if (_isMe && viewerHasAccess) {
      tabs.add('curator');
    } else if (!_isMe && viewerHasAccess && ownerIsCurator) {
      tabs.add('curator');
    }

    tabs.add('maker');
    tabs.add('index');
    tabs.add('collection');

    int tabIndex = _currentTabIndex;
    String? savedMainTab = _tempSavedMainTab;

    if (_isMe && _viewerAccount != null && _viewerAccount!.preferences.containsKey('profile')) {
      final profilePrefs = Map<String, dynamic>.from(_viewerAccount!.preferences['profile'] as Map? ?? {});
      savedMainTab = profilePrefs['mainTab'] as String?;
      _showDrafts = profilePrefs['showDrafts'] as bool? ?? _showDrafts;
      _curatorSubTabIndex = profilePrefs['curatorSubTab'] as int? ?? _curatorSubTabIndex;
      _indexSubTabIndex = profilePrefs['indexSubTab'] as int? ?? _indexSubTabIndex;
      _settingsSubTabIndex = profilePrefs['settingsSubTab'] as int? ?? _settingsSubTabIndex;
    }

    if (savedMainTab != null && tabs.contains(savedMainTab)) {
      tabIndex = tabs.indexOf(savedMainTab);
    } else {
      final defaultIdx = tabs.indexOf('maker');
      tabIndex = defaultIdx != -1 ? defaultIdx : 0;
    }

    setState(() {
      _visibleTabs = tabs;
      _currentTabIndex = tabIndex;
      _isLoading = false;
    });
  }

  void _savePrefs({String? newMainTab}) {
    if (!_isMe) return;
    final uid = getCurrentUserId();
    if (uid == null) return;

    final mainTab = newMainTab ?? (_currentTabIndex < _visibleTabs.length ? _visibleTabs[_currentTabIndex] : '');
    if (mainTab.isEmpty) return;

    final prefsData = {
      'mainTab': mainTab,
      'showDrafts': _showDrafts,
      'curatorSubTab': _curatorSubTabIndex,
      'indexSubTab': _indexSubTabIndex,
      'settingsSubTab': _settingsSubTabIndex,
    };

    try {
      saveLocalPreference('profile_sticky_prefs_$uid', jsonEncode(prefsData));
    } catch (_) {}

    fsUpdateDoc('Users/$uid', jsonEncode({
      'preferences.profile': prefsData
    })).catchError((_) {
      fsSetDoc('Users/$uid', jsonEncode({
        'preferences': {
          'profile': prefsData
        }
      }), true);
    });
  }

  void _setupWorksPipeline() {
    _worksSub?.callAsFunction();
    _worksSub = fsListenQuery('fanzines', 'editorId', '==', jsonEncode(_targetUid), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final works = decoded.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['id'] = d['id'];
          return data;
        }).toList();
        setState(() {
          _userWorks = works;
        });
      } catch (e) {
        print("Error loading works: $e");
      }
    });
  }

  void _setupMentionsPipeline() {
    final String currentDisplayName = _profileData?.displayName ?? '';
    if (currentDisplayName.isEmpty) return;
    _mentionsSub?.callAsFunction();
    _mentionsSub = fsListenQuery('fanzines', 'draftEntities', 'array-contains', jsonEncode(currentDisplayName), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final fanzines = decoded.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['id'] = d['id'];
          return data;
        }).toList();
        setState(() {
          _userMentions = fanzines;
        });
      } catch (e) {
        print("Error loading mentions: $e");
      }
    });
  }

  void _setupCommentsPipeline() {
    _commentsSub?.callAsFunction();
    _commentsSub = fsListenQuery('artifacts/bqopd/public/data/comments', 'userId', '==', jsonEncode(_targetUid), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final list = decoded.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['_id'] = d['id'];
          return data;
        }).toList();
        setState(() {
          _userComments = list;
        });
      } catch (e) {
        print("Error loading comments: $e");
      }
    });
  }

  void _setupManagedProfilesPipeline() {
    _managedSub?.callAsFunction();
    _managedSub = fsListenQuery('profiles', 'isManaged', '==', jsonEncode(true), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final profiles = decoded.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['id'] = d['id'];
          return data;
        }).where((p) {
          final List managers = p['managers'] ?? [];
          return managers.contains(_targetUid);
        }).toList();
        setState(() {
          _allManagedProfiles = profiles;
        });
      } catch (e) {
        print("Error parsing managed profiles: $e");
      }
    });
  }

  void _setupSystemUsersPipeline() {
    _usersSub?.callAsFunction();
    _usersSub = fsListenQuery('Users', '', '', '', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final users = decoded.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['id'] = d['id'];
          return data;
        }).toList();
        setState(() {
          _allSystemUsers = users;
        });
      } catch (e) {
        print("Error loading users: $e");
      }
    });
  }

  void _setupTrainingDataPipeline() {
    _trainingSub?.callAsFunction();
    _trainingSub = fsListenQuery('images', 'isTrainingData', '==', jsonEncode(true), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final list = decoded.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['id'] = d['id'];
          return data;
        }).toList();
        setState(() {
          _aiTrainingData = list;
        });
      } catch (e) {
        print("Error loading AI training logs: $e");
      }
    });
  }

  Future<void> _handleFollowToggle() async {
    final currentUid = component.authState?.user?.uid;
    if (currentUid == null) return;
    final nextStatus = !_isFollowing;
    setState(() {
      _isFollowing = nextStatus;
    });
    if (nextStatus) {
      await fsSetDoc('profiles/$currentUid/following/$_targetUid', jsonEncode({'followedAt': WebFieldValue.serverTimestamp()}), true);
      await fsSetDoc('profiles/$_targetUid/followers/$currentUid', jsonEncode({'followerAt': WebFieldValue.serverTimestamp()}), true);
      await fsUpdateDoc('profiles/$currentUid', jsonEncode({'followingCount': WebFieldValue.increment(1)}));
      await fsUpdateDoc('profiles/$_targetUid', jsonEncode({'followerCount': WebFieldValue.increment(1)}));
    } else {
      await fsDeleteDoc('profiles/$currentUid/following/$_targetUid');
      await fsDeleteDoc('profiles/$_targetUid/followers/$currentUid');
      await fsUpdateDoc('profiles/$currentUid', jsonEncode({'followingCount': WebFieldValue.increment(-1)}));
      await fsUpdateDoc('profiles/$_targetUid', jsonEncode({'followerCount': WebFieldValue.increment(-1)}));
    }
  }

  Component _buildMainNavigationTab(String name, int index) {
    final bool isActive = _currentTabIndex == index;
    return span([
      text(name.toLowerCase())
    ],
        classes: isActive ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
        events: {
          'click': (e) {
            setState(() {
              _currentTabIndex = index;
            });
            _savePrefs(newMainTab: _visibleTabs[index]);
          }
        });
  }

  Component _buildContentBody(String tabName) {
    final isViewerAdmin = _viewerAccount?.role == 'admin' || (_viewerAccount?.roles.contains('admin') ?? false);
    final isViewerModerator = _viewerAccount?.role == 'moderator' || (_viewerAccount?.roles.contains('moderator') ?? false);
    final isViewerCurator = _viewerAccount?.role == 'curator' || (_viewerAccount?.roles.contains('curator') ?? false) || (_viewerAccount?.isCurator ?? false);

    switch (tabName) {
      case 'maker':
        return MakerTab(
          userWorks: _userWorks,
          isMe: _isMe,
          canSeeDrafts: _isMe || isViewerAdmin || isViewerModerator || isViewerCurator,
          targetUserId: _targetUid,
          authState: component.authState,
          initialShowDrafts: _showDrafts,
          onDraftsToggle: (val) {
            setState(() => _showDrafts = val);
            _savePrefs();
          },
        );
      case 'index':
        return IndexTab(
          mentions: _userMentions,
          comments: _userComments,
          initialSubTab: _indexSubTabIndex,
          onSubTabChanged: (val) {
            setState(() => _indexSubTabIndex = val);
            _savePrefs();
          },
        );
      case 'settings':
        return SettingsTab(
          viewerAccount: _viewerAccount,
          targetUserId: _targetUid,
          isMe: _isMe,
          allManagedProfiles: _allManagedProfiles,
          allSystemUsers: _allSystemUsers,
          initialSubTab: _settingsSubTabIndex,
          onSubTabChanged: (val) {
            setState(() => _settingsSubTabIndex = val);
            _savePrefs();
          },
        );
      case 'curator':
        return CuratorTab(
          userWorks: _userWorks,
          aiTrainingData: _aiTrainingData,
          initialSubTab: _curatorSubTabIndex,
          onSubTabChanged: (val) {
            setState(() => _curatorSubTabIndex = val);
            _savePrefs();
          },
        );
      case 'collection':
      default:
        return div([
          span([text('analytics')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 56px;'}),
          h3([text('${tabName.toUpperCase()} coming soon')], classes: 'font-bold text-black text-lg mt-4'),
          p([text('Archival features are currently being generated on our backend.')], classes: 'text-sm text-gray mt-2')
        ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }
  }

  @override
  Component build(BuildContext context) {
    if (_isLoading) {
      return div(
          classes: 'flex-col items-center justify-center w-full',
          attributes: {'style': 'min-height: 100vh;'},
          [p([text('Loading profile...')])]);
    }

    if (_errorMessage != null) {
      return div(
          classes: 'flex-col items-center justify-center w-full',
          attributes: {'style': 'min-height: 100vh;'},
          [p(classes: 'error-msg', [text(_errorMessage!)])]);
    }

    return div([
      div([
        // Header profile envelope card
        ProfileCard(
          profile: _profileData!,
          isMe: _isMe,
          isFollowing: _isFollowing,
          onFollowToggle: _handleFollowToggle,
        ),

        div([], classes: 'profile-spacer'),

        // Tab selection row
        if (_visibleTabs.isNotEmpty)
          div([
            for (int i = 0; i < _visibleTabs.length; i++) ...[
              _buildMainNavigationTab(_visibleTabs[i], i),
              if (i < _visibleTabs.length - 1)
                span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
            ]
          ], classes: 'bg-white rounded-md shadow-sm py-4', attributes: const {'style': 'display: flex; justify-content: center; align-items: center; overflow-x: auto; box-sizing: border-box; width: 100%;'}),

        div([], classes: 'profile-spacer'),

        // Content Area
        if (_visibleTabs.isNotEmpty)
          _buildContentBody(_visibleTabs[_currentTabIndex])

      ], classes: 'unified-profile-column')
    ], attributes: const {
      'style': 'min-height: 100vh; background-color: #e5e5e5; display: flex; flex-direction: column; align-items: center; justify-content: flex-start; padding-top: 16px; padding-bottom: 80px; box-sizing: border-box;'
    });
  }
}