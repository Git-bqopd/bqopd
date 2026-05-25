import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';

import '../utils/web_firebase_interop.dart';
import '../utils/firebase_mocks.dart';
import '../utils/icon_utils.dart';
import '../utils/web_utils.dart';
import '../utils/web_shortcode_service.dart';
import '../utils/unsaved_fanzine_registry.dart';
import '../components/page_wrapper.dart';

/// Fully-featured profile rendering that matches the visual aesthetics and sub-tab
/// modularity of the Flutter application.
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

  // Sub-tabs index tracking
  int _settingsSubTabIndex = 0; // 0: shortcodes, 1: managed profiles, 2: permissions, 3: social buttons
  int _curatorSubTabIndex = 0;  // 0: curator, 1: publisher, 2: entities, 3: ai training data
  int _indexSubTabIndex = 0;    // 0: mentions, 1: comments
  int _socialSubTabIndex = 0;   // 0: socials, 1: affiliations, 2: upcoming

  // Sub-tab specific settings states
  String _loginZineShortcode = '';
  String _registerZineShortcode = '';
  bool _isSavingSettings = false;

  // New Managed Profile Inputs
  String _newManagedFirstName = '';
  String _newManagedLastName = '';
  String _newManagedBio = '';
  bool _isCreatingManagedProfile = false;

  // Toggles for Maker Tab
  bool _showDrafts = false;

  // Maker Options Modal state
  bool _showMakerModal = false;
  String _makerModalMode = 'options'; // 'options', 'upload'
  String _uploadTitle = '';
  String _uploadDescription = '';
  String _uploadIndicia = '';
  String? _uploadError;
  bool _isUploadingImage = false;

  // High-fidelity Image Upload States matching Flutter
  String? _uploadImageBase64;
  String? _uploadImageName;
  String? _uploadPreviewUrl;
  List<Map<String, dynamic>> _uploadCreators = [];
  String _newCreatorHandle = '';
  String _newCreatorRole = '';

  // Stream Subscriptions
  StreamSubscription? _profileSub;
  StreamSubscription? _followSub;
  StreamSubscription? _viewerAccountSub;
  StreamSubscription? _viewerProfileSub;

  // Custom Local Queries to power lists
  List<Map<String, dynamic>> _userWorks = [];
  List<Map<String, dynamic>> _userMentions = [];
  List<Map<String, dynamic>> _userComments = [];
  Map<String, bool> _socialButtonVisibility = {};
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

  List<Map<String, dynamic>> get _publishedWorks => _userWorks.where((w) => w['isLive'] == true).toList();
  List<Map<String, dynamic>> get _draftWorks => _userWorks.where((w) => w['isLive'] != true).toList();

  @override
  void initState() {
    super.initState();
    // DEFER data pipeline initialization ONLY on the client-side browser context.
    // This completely prevents the server-side renderer from scheduling unsupported reactive frames.
    if (kIsWeb) {
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

    // RULE: If we hit '/profile' directly (userId is null) and we are authenticated,
    // immediately replace route path with our clean handle (e.g. '/kevin')
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

    // 1. Listen to target user profile
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

    // 2. Listen to Follow Status (if guest/other user)
    if (!_isMe && currentUid != null) {
      _followSub = component.engagementRepository.isFollowing(_targetUid).listen((following) {
        setState(() {
          _isFollowing = following;
        });
      });
    }

    // 3. Listen to viewer account to determine roles
    if (currentUid != null) {
      _viewerAccountSub = component.userRepository.watchUserAccount(currentUid).listen((account) {
        if (account != null) {
          setState(() {
            _viewerAccount = account;
            if (account.preferences.containsKey('socialButtons')) {
              _socialButtonVisibility = Map<String, bool>.from(account.preferences['socialButtons']);
            }
            _rebuildTabSchema();
          });
        }
      });
    }

    // 4. Load works and images for the Maker tab
    _setupWorksPipeline();
    _setupCommentsPipeline();
    _loadGlobalSettings();
    _setupManagedProfilesSettings();
    _setupSystemUsersPipeline();
    _setupTrainingDataPipeline();
  }

  void _setupManagedProfilesSettings() {
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
      } catch (_) {}
    });
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

    setState(() {
      _visibleTabs = tabs;
      if (_currentTabIndex >= tabs.length) {
        _currentTabIndex = tabs.indexOf('maker');
        if (_currentTabIndex == -1) _currentTabIndex = 0;
      }
      _isLoading = false;
    });
  }

  void _setupWorksPipeline() {
    _worksSub?.callAsFunction();
    // Fetch user works directly
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
      } catch (_) {}
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
      } catch (_) {}
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
      } catch (_) {}
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
      } catch (_) {}
    });
  }

  Future<void> _loadGlobalSettings() async {
    try {
      final res = await fsGetDoc('app_settings/main_settings');
      final doc = jsonDecode(res);
      if (doc['exists'] == true) {
        setState(() {
          _loginZineShortcode = doc['data']['login_zine_shortcode'] ?? '';
          _registerZineShortcode = doc['data']['register_zine_shortcode'] ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _saveGlobalSettings() async {
    setState(() => _isSavingSettings = true);
    try {
      await fsSetDoc('app_settings/main_settings', jsonEncode({
        'login_zine_shortcode': _loginZineShortcode.trim(),
        'register_zine_shortcode': _registerZineShortcode.trim()
      }), true);
    } catch (_) {}
    setState(() => _isSavingSettings = false);
  }

  Future<void> _createManagedProfile() async {
    if (_newManagedFirstName.trim().isEmpty || _newManagedLastName.trim().isEmpty) return;
    setState(() => _isCreatingManagedProfile = true);

    try {
      final String baseHandle = "${_newManagedFirstName.trim()}-${_newManagedLastName.trim()}"
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9-]'), '-');

      final String uniqueId = 'managed_${DateTime.now().millisecondsSinceEpoch}';

      final publicData = {
        'uid': uniqueId,
        'username': baseHandle,
        'displayName': "${_newManagedFirstName.trim()} ${_newManagedLastName.trim()}",
        'bio': _newManagedBio.trim(),
        'photoUrl': '',
        'isManaged': true,
        'isCurator': false,
        'isAdmin': false,
        'managers': [_targetUid],
        'followerCount': 0,
        'followingCount': 0,
        'updatedAt': WebFieldValue.serverTimestamp()
      };

      await fsSetDoc('profiles/$uniqueId', jsonEncode(publicData), true);
      await fsSetDoc('usernames/$baseHandle', jsonEncode({
        'uid': uniqueId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);

      setState(() {
        _newManagedFirstName = '';
        _newManagedLastName = '';
        _newManagedBio = '';
        _isCreatingManagedProfile = false;
      });
    } catch (e) {
      print("Error creating managed profile: $e");
      setState(() => _isCreatingManagedProfile = false);
    }
  }

  Future<void> _toggleSocialButtonVisibility(String toolId) async {
    final currentVal = _socialButtonVisibility[toolId] ?? true;
    final nextVal = !currentVal;

    setState(() {
      _socialButtonVisibility[toolId] = nextVal;
    });

    await fsUpdateDoc('Users/$_targetUid', jsonEncode({
      'preferences.socialButtons.$toolId': nextVal
    }));
  }

  Future<void> _updateUserPermission(String uid, String newRole) async {
    final bool isCurator = newRole == 'curator' || newRole == 'admin' || newRole == 'moderator';

    await fsUpdateDoc('Users/$uid', jsonEncode({
      'role': newRole,
      'isCurator': isCurator
    }));

    await fsUpdateDoc('profiles/$uid', jsonEncode({
      'isCurator': isCurator,
      'isAdmin': newRole == 'admin'
    }));
  }

  Future<void> _toggleFollow() async {
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

  /// High-efficiency local checker for database collisions prior to reserving a shortcode key.
  Future<String> _generateUniqueTempShortcode() async {
    final String? email = component.authState?.user?.email;
    final bool useVanity = email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';

    bool isUnique = false;
    String code = "";
    int retries = 0;
    while (!isUnique && retries < 15) {
      final String candidate = useVanity
          ? ShortcodeGenerator.generateVanityCode()
          : ShortcodeGenerator.generateStandardCode();
      final String codeUpper = candidate.toUpperCase();

      final docRes = await fsGetDoc('shortcodes/$codeUpper');
      final Map<String, dynamic> doc = jsonDecode(docRes) as Map<String, dynamic>;

      final userRes = await fsGetDoc('usernames/${codeUpper.toLowerCase()}');
      final Map<String, dynamic> unDoc = jsonDecode(userRes) as Map<String, dynamic>;

      final isLocalCollision = UnsavedFanzineRegistry.hasCode(candidate);

      if (doc['exists'] != true && unDoc['exists'] != true && !isLocalCollision) {
        isUnique = true;
        code = candidate;
      }
      retries++;
    }
    if (code.isEmpty) {
      code = 'TEMP_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    }
    return code;
  }

  Future<void> _createFolio() async {
    setState(() => _isLoading = true);
    try {
      final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
      final shortCode = await _generateUniqueTempShortcode();

      final newFanzine = Fanzine(
        id: fanzineId,
        title: 'new folio name',
        ownerId: _targetUid,
        type: FanzineType.folio,
        isLive: false,
        processingStatus: 'complete',
        shortCode: shortCode,
        twoPage: true,
        hasCover: true,
        editors: const [],
        draftEntities: const [],
        masterCreators: const [],
      );

      // Register fanzine locally in memory
      UnsavedFanzineRegistry.add(newFanzine, []);

      setState(() {
        _showMakerModal = false;
      });
      if (mounted) {
        Router.of(context).replace('/$shortCode'); // Navigate directly to shortcode URL
      }
    } catch (e) {
      print("Error creating folio: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createCalendar() async {
    setState(() => _isLoading = true);
    try {
      final fanzineId = 'calendar_${DateTime.now().millisecondsSinceEpoch}';
      final shortCode = await _generateUniqueTempShortcode();

      final newFanzine = Fanzine(
        id: fanzineId,
        title: 'Convention Calendar 2026',
        ownerId: _targetUid,
        type: FanzineType.calendar,
        isLive: false,
        processingStatus: 'complete',
        shortCode: shortCode,
        twoPage: true,
        hasCover: true,
        editors: const [],
        draftEntities: const [],
        masterCreators: const [],
      );

      final page1Id = 'page1_${DateTime.now().millisecondsSinceEpoch}';
      final page2Id = 'page2_${DateTime.now().millisecondsSinceEpoch}';

      final List<FanzinePage> pages = [
        FanzinePage(
          id: page1Id,
          pageNumber: 1,
          templateId: 'calendar_left',
          status: 'ready',
        ),
        FanzinePage(
          id: page2Id,
          pageNumber: 2,
          templateId: 'calendar_right',
          status: 'ready',
        ),
      ];

      // Register fanzine locally in memory
      UnsavedFanzineRegistry.add(newFanzine, pages);

      setState(() {
        _showMakerModal = false;
      });
      if (mounted) {
        Router.of(context).replace('/$shortCode'); // Navigate directly to fanzine shortcode URL
      }
    } catch (e) {
      print("Error creating calendar: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Pick local file and build pre-render client preview matching Flutter
  void _pickAndPreviewImage() {
    triggerFilePicker('maker-upload-picker', (base64, fileName, objectUrl) {
      setState(() {
        _uploadImageBase64 = base64;
        _uploadImageName = fileName;
        _uploadPreviewUrl = objectUrl;
        _uploadError = null;
      });
    });
  }

  // Handle dynamic file upload changes from the transparent native file input
  void _onFileInputChanged() {
    readSelectedFile('maker-upload-picker', (base64, fileName, objectUrl) {
      setState(() {
        _uploadImageBase64 = base64;
        _uploadImageName = fileName;
        _uploadPreviewUrl = objectUrl;
        _uploadError = null;
      });
    });
  }

  // Handle dynamic creators lookups matching Flutter
  Future<void> _addCreator() async {
    final handle = _newCreatorHandle.trim();
    final role = _newCreatorRole.trim();
    if (handle.isEmpty) return;

    final cleanHandle = handle.toLowerCase().replaceAll('@', '');
    String resolvedName = handle;
    String? resolvedUid;

    try {
      final resStr = await fsQuery('profiles', 'username', '==', jsonEncode(cleanHandle), '');
      final List docs = jsonDecode(resStr);
      if (docs.isNotEmpty) {
        final doc = docs.first;
        final data = doc['data'];
        resolvedName = data['displayName'] ?? data['username'] ?? handle;
        resolvedUid = doc['id'];
      }
    } catch (e) {
      print("Error looking up user by handle: $e");
    }

    setState(() {
      _uploadCreators.add({
        'uid': resolvedUid,
        'name': resolvedName,
        'role': role.isNotEmpty ? role : 'Contributor',
      });
      _newCreatorHandle = '';
      _newCreatorRole = '';
    });
  }

  // High fidelity publication pipeline matching Flutter
  Future<void> _submitSingleImage() async {
    if (_uploadTitle.trim().isEmpty) {
      setState(() => _uploadError = "Title is required.");
      return;
    }
    if (_uploadImageBase64 == null) {
      setState(() => _uploadError = "Please select or capture an image first.");
      return;
    }

    setState(() {
      _isUploadingImage = true;
      _uploadError = null;
    });

    try {
      final Uint8List bytes = base64Decode(_uploadImageBase64!);
      final String path = 'uploads/$_targetUid/folio_assets/img_${DateTime.now().millisecondsSinceEpoch}_$_uploadImageName';

      // Perform secure upload to Storage via interop
      final String downloadUrl = await stUpload(path, bytes, 'image/jpeg');

      final imageId = 'img_${DateTime.now().millisecondsSinceEpoch}';

      // Strict inlined owner check for vanity eligibility to prevent other users from obtaining vanity URLs
      final String? email = component.authState?.user?.email;
      final bool useVanity = email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';

      // Generate and register shortcode for image using shared logic!
      final shortCode = await WebShortcodeService.assignShortcode(
        contentType: 'image',
        contentId: imageId,
        isVanity: useVanity,
      ) ?? imageId.substring(imageId.length - 7).toUpperCase();

      final imgData = {
        'uid': _targetUid,
        'uploaderId': _targetUid,
        'fileUrl': downloadUrl,
        'fileName': _uploadImageName,
        'title': _uploadTitle.trim(),
        'description': _uploadDescription.trim(),
        'status': 'approved',
        'tags': {},
        'indicia': _uploadIndicia.trim(),
        'creators': _uploadCreators,
        'timestamp': WebFieldValue.serverTimestamp(),
        'shortCode': shortCode,
        'storagePath': path,
      };

      await fsSetDoc('images/$imageId', jsonEncode(imgData), true);

      final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';

      // Generate and register shortcode for parent fanzine!
      final fzShortCode = await WebShortcodeService.assignShortcode(
        contentType: 'fanzine',
        contentId: fanzineId,
        isVanity: useVanity,
      ) ?? fanzineId.substring(fanzineId.length - 7).toUpperCase();

      final fzData = {
        'title': _uploadTitle.trim(),
        'ownerId': _targetUid,
        'editorId': _targetUid,
        'editors': [],
        'isLive': false,
        'processingStatus': 'complete',
        'creationDate': WebFieldValue.serverTimestamp(),
        'type': 'folio',
        'shortCode': fzShortCode,
        'shortCodeKey': fzShortCode.toUpperCase(),
        'twoPage': false,
      };
      await fsSetDoc('fanzines/$fanzineId', jsonEncode(fzData), true);

      final pageId = 'page_${DateTime.now().millisecondsSinceEpoch}';
      await fsSetDoc('fanzines/$fanzineId/pages/$pageId', jsonEncode({
        'imageId': imageId,
        'imageUrl': downloadUrl,
        'pageNumber': 1,
        'status': 'ready',
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);

      await fsUpdateDoc('images/$imageId', jsonEncode({
        'usedInFanzines': WebFieldValue.arrayUnion([fanzineId])
      }));

      setState(() {
        _showMakerModal = false;
        _uploadTitle = '';
        _uploadDescription = '';
        _uploadIndicia = '';
        _uploadImageBase64 = null;
        _uploadImageName = null;
        _uploadPreviewUrl = null;
        _uploadCreators = [];
      });

      if (mounted) {
        Router.of(context).replace('/$fzShortCode'); // Navigate directly to fanzine shortcode URL
      }
    } catch (e) {
      setState(() => _uploadError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (_isLoading) {
      return div([
        div([
          div([], classes: 'shimmer-bg w-16 h-16 rounded-full', attributes: const {'style': 'margin-bottom: 12px;'}),
          p([text("Connecting to bqopd database...")], classes: 'text-sm text-gray font-bold italic')
        ], classes: 'flex-col items-center justify-center gap-3')
      ], attributes: const {'style': 'min-height: 100vh; display: flex; align-items: center; justify-content: center; background-color: #f3f4f6;'});
    }

    if (_errorMessage != null) {
      return div([
        PageWrapper(
            child: div([
              h1([text("Access Restricted")], classes: 'font-bold text-lg text-red-500'),
              p([text(_errorMessage!)]),
              a([text("Log In Here")], href: '/login', classes: 'nav-pill')
            ], classes: 'flex-col items-center gap-4')
        )
      ], attributes: const {'style': 'min-height: 100vh; display: flex; align-items: center; justify-content: center; background-color: #f3f4f6;'});
    }

    final String displayName = _profileData?.displayName ?? _profileData?.username ?? 'Archival Human';
    final String username = _profileData?.username ?? 'archival';
    final String bio = _profileData?.bio ?? '';
    final String photoUrl = _profileData?.photoUrl ?? '';

    return div([
      div([
        // Row 1: The Profile Header Card (Aesthetic desktop or mobile blocks)
        div([
          div([
            _buildLeftCardDetailsPart(displayName, username, bio, photoUrl, isMobile: false),
            div([], classes: 'profile-desktop-divider'),
            _buildRightCardSocialsPart(isMobile: false)
          ], classes: 'white-sticker-8-5')
        ], classes: 'envelope-8-5-desktop'),

        div([
          div([
            div([
              _buildLeftCardDetailsPart(displayName, username, bio, photoUrl, isMobile: true)
            ], classes: 'white-sticker-mobile-8-5')
          ], classes: 'envelope-8-5-mobile-item'),
          div([
            div([
              _buildRightCardSocialsPart(isMobile: true)
            ], classes: 'white-sticker-mobile-8-5')
          ], classes: 'envelope-8-5-mobile-item')
        ], classes: 'envelope-8-5-mobile-container'),

        // Row 2: Spacer
        div([], classes: 'profile-spacer'),

        // Row 3: The Category Tabs
        if (_visibleTabs.isNotEmpty)
          div([
            for (int i = 0; i < _visibleTabs.length; i++) ...[
              _buildMainNavigationTab(_visibleTabs[i], i),
              if (i < _visibleTabs.length - 1)
                span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
            ]
          ], classes: 'bg-white rounded-md shadow-sm py-4', attributes: const {'style': 'display: flex; justify-content: center; align-items: center; overflow-x: auto; box-sizing: border-box; width: 100%;'}),

        // Row 4: Spacer
        div([], classes: 'profile-spacer'),

        // Row 5: The Action Utility Bar & Sub-navigation configurations
        if (_visibleTabs.isNotEmpty)
          _buildActiveActionUtilityBar(_visibleTabs[_currentTabIndex]),

        // Row 6: Spacer
        div([], classes: 'profile-spacer'),

        // Row 7: The Content Pane
        div([
          if (_visibleTabs.isNotEmpty)
            _buildActiveTabContent(_visibleTabs[_currentTabIndex])
        ], attributes: const {'style': 'width: 100%; box-sizing: border-box;'})
      ], classes: 'unified-profile-column'),

      if (_showMakerModal)
        _buildMakerModalOverlay(),
    ], attributes: const {
      'style': 'min-height: 100vh; background-color: #e5e5e5; display: flex; flex-direction: column; align-items: center; justify-content: flex-start; padding-top: 16px; padding-bottom: 80px; box-sizing: border-box;'
    });
  }

  Component _buildLeftCardDetailsPart(String displayName, String username, String bio, String photoUrl, {required bool isMobile}) {
    return div([
      // Upper subrow: Avatar left, Edit Info & Followers on right
      div([
        // Avatar Circle
        div([
          if (photoUrl.isNotEmpty)
            img(src: photoUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
          else
            span([
              text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')
            ], attributes: const {'style': 'font-size: 28px; font-weight: bold; color: #999;'})
        ], attributes: const {
          'style': 'width: 72px; height: 72px; border-radius: 50%; background-color: #eee; overflow: hidden; border: 2px solid #ccc; display: flex; justify-content: center; align-items: center;'
        }),

        span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),

        // Edit Button / Followers Details
        div([
          if (!_isMe)
            button(
                [text(_isFollowing ? 'unfollow' : 'follow')],
                classes: _isFollowing ? 'profile-btn text-red-500' : 'profile-btn',
                attributes: const {'style': 'width: 100px; height: 28px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border-radius: 0px !important; cursor: pointer; border: 1px solid black;'},
                events: {'click': (e) => _toggleFollow()}
            )
          else
            a(
                [text('edit info')],
                href: '/edit-info',
                classes: 'profile-btn',
                attributes: const {'style': 'width: 100px; height: 28px; display: inline-flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-align: center; border: 1px solid #ddd; border-radius: 0px !important;'}
            ),

          div([], attributes: const {'style': 'height: 4px;'}),
          div([
            span([text('${_profileData?.followerCount ?? 0} followers')], attributes: const {'style': 'text-decoration: underline; margin-right: 8px;'}),
            span([text('${_profileData?.followingCount ?? 0} following')], attributes: const {'style': 'text-decoration: underline;'})
          ], attributes: const {'style': 'font-size: 10px; font-weight: 500; color: #555; display: flex;'})
        ], attributes: const {'style': 'display: flex; flex-direction: column; align-items: flex-start; justify-content: center;'})
      ], attributes: const {'style': 'display: flex; align-items: center; justify-content: center;'}),

      div([], attributes: const {'style': 'height: 12px;'}),

      // Underneath row: Display Name, Username and Bio
      h1([text(displayName)], attributes: const {'style': 'font-size: 18px; font-weight: 900; margin: 0; color: black; line-height: 1.2;'}),
      p([text('@$username')], attributes: const {'style': 'font-size: 12px; color: #666; margin: 2px 0 0 0;'}),

      if (bio.isNotEmpty) ...[
        div([], attributes: const {'style': 'height: 8px;'}),
        p([text(bio)], attributes: const {
          'style': 'font-size: 11px; color: #444; font-style: italic; margin-top: 4px; line-height: 1.4; max-width: 280px; text-align: center;'
        })
      ]
    ], classes: isMobile ? '' : 'profile-desktop-left');
  }

  Component _buildRightCardSocialsPart({required bool isMobile}) {
    return div([
      // Tab headers: socials, affiliations, upcoming
      div([
        _buildSocialHeaderMiniTab("socials", 0),
        span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
        _buildSocialHeaderMiniTab("affiliations", 1),
        span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
        _buildSocialHeaderMiniTab("upcoming", 2)
      ], classes: 'py-2 bg-gray-100 rounded-md', attributes: const {'style': 'display: flex; justify-content: center; margin-bottom: 16px;'}),

      // Active Tab List Content
      if (_socialSubTabIndex == 0) ...[
        _buildSocialLinkButton("X / Twitter", _profileData?.xHandle, "https://x.com/"),
        _buildSocialLinkButton("Instagram", _profileData?.instagramHandle, "https://instagram.com/"),
        _buildSocialLinkButton("GitHub", _profileData?.githubHandle, "https://github.com/"),

        if ((_profileData?.xHandle ?? '').isEmpty &&
            (_profileData?.instagramHandle ?? '').isEmpty &&
            (_profileData?.githubHandle ?? '').isEmpty)
          div([
            span([text('contact_mail')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 32px;'}),
            p([text("No external accounts linked.")], attributes: const {'style': 'font-size: 11px; color: #999; font-style: italic; margin-top: 4px;'})
          ], attributes: const {'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100px; flex: 1;'})
      ] else if (_socialSubTabIndex == 1)
        div([
          p([text("Affiliations Coming Soon")], attributes: const {'style': 'font-size: 12px; color: #999; font-style: italic;'})
        ], attributes: const {'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1;'})
      else if (_socialSubTabIndex == 2)
          div([
            p([text("Upcoming Events Coming Soon")], attributes: const {'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1;'})
          ], attributes: const {'style': 'display: flex; align-items: center; justify-content: center; min-height: 100px; flex: 1;'})
        else
          div([]),

      div([], attributes: const {'style': 'flex: 1;'}),

      // Logout at the bottom right
      if (_isMe)
        div([
          button(
              [text('logout')],
              classes: 'btn-logout',
              attributes: const {'style': 'font-size: 12px; font-weight: bold; text-decoration: underline; background: none; border: none; cursor: pointer; color: black;'},
              events: {'click': (e) => component.authBloc.add(LogoutRequested())}
          )
        ], attributes: const {'style': 'display: flex; justify-content: flex-end; margin-top: 12px;'})
    ], classes: isMobile ? 'w-full h-full' : 'profile-desktop-right', attributes: isMobile ? const {'style': 'display: flex; flex-direction: column;'} : null);
  }

  Component _buildSocialHeaderMiniTab(String title, int idx) {
    final bool isSelected = _socialSubTabIndex == idx;
    return span([
      text(title)
    ], classes: isSelected ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
      'click': (e) => setState(() => _socialSubTabIndex = idx)
    });
  }

  Component _buildSocialLinkButton(String platform, String? handle, String baseUrl) {
    if (handle == null || handle.trim().isEmpty) return div([]);

    return a(
        [
          span([
            text(platform.startsWith('X') ? 'link' : 'alternate_email')
          ], classes: 'material-symbols-outlined text-gray-500', attributes: const {'style': 'font-size: 16px;'}),
          span([text('$platform: ')], attributes: const {'style': 'font-size: 11px; font-weight: bold; color: black; margin-left: 8px;'}),
          span([text('@$handle')], classes: 'handle-text')
        ],
        href: '$baseUrl$handle',
        classes: 'social-link-button',
        attributes: const {
          'target': '_blank'
        }
    );
  }

  Component _buildMainNavigationTab(String name, int index) {
    final bool isActive = _currentTabIndex == index;

    return span([
      text(name.toLowerCase())
    ],
        classes: isActive
            ? 'text-xs font-bold text-black border-b border-black cursor-pointer'
            : 'text-xs text-gray cursor-pointer',
        events: {
          'click': (e) {
            setState(() {
              _currentTabIndex = index;
            });
          }
        });
  }

  Component _buildPlainTextTab({
    required String title,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return span([
      text(title.toLowerCase())
    ],
        classes: isActive
            ? 'text-xs font-bold text-black border-b border-black cursor-pointer'
            : 'text-xs text-gray cursor-pointer',
        events: {
          'click': (e) => onTap(),
        });
  }

  Component _buildActiveActionUtilityBar(String tabName) {
    final bool isViewerAdmin = _viewerAccount?.role == 'admin' || (_viewerAccount?.roles.contains('admin') ?? false);

    switch (tabName) {
      case 'maker':
        final bool viewerCanSeeDrafts = _isMe || (_viewerAccount?.role == 'admin') || (_viewerAccount?.role == 'moderator') || (_viewerAccount?.isCurator ?? false);
        return div([
          div([
            if (_isMe) ...[
              button(
                  [text("make")],
                  classes: 'profile-btn',
                  attributes: const {'style': 'width: 100px; height: 28px; display: inline-flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-align: center; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer;'},
                  events: {
                    'click': (e) {
                      setState(() {
                        _showMakerModal = true;
                        _makerModalMode = 'options';
                        _uploadError = null;
                      });
                    }
                  }
              ),
              span([], attributes: const {'style': 'display: inline-block; width: 12px;'}),
            ],
            _buildPlainTextTab(
              title: "published",
              isActive: !_showDrafts,
              onTap: () => setState(() => _showDrafts = false),
            ),
            if (viewerCanSeeDrafts) ...[
              span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
              _buildPlainTextTab(
                title: "drafts",
                isActive: _showDrafts,
                onTap: () => setState(() => _showDrafts = true),
              ),
            ]
          ], attributes: const {'style': 'display: flex; align-items: center; justify-content: center; width: 100%;'})
        ], classes: 'bg-white rounded-md p-4 shadow-sm flex-row items-center justify-center', attributes: const {'style': 'display: flex; flex-wrap: wrap; gap: 12px; box-sizing: border-box; width: 100%;'});

      case 'index':
        return div([
          _buildPlainTextTab(
            title: "mentions (${_userMentions.length})",
            isActive: _indexSubTabIndex == 0,
            onTap: () => setState(() => _indexSubTabIndex = 0),
          ),
          span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
          _buildPlainTextTab(
            title: "comments (${_userComments.length})",
            isActive: _indexSubTabIndex == 1,
            onTap: () => setState(() => _indexSubTabIndex = 1),
          ),
        ], classes: 'bg-white rounded-md p-4 shadow-sm', attributes: const {'style': 'display: flex; justify-content: center; align-items: center; box-sizing: border-box; width: 100%;'});

      case 'curator':
        return div([
          _buildPlainTextTab(
            title: "curator inbox",
            isActive: _curatorSubTabIndex == 0,
            onTap: () => setState(() => _curatorSubTabIndex = 0),
          ),
          span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
          _buildPlainTextTab(
            title: "publisher queue",
            isActive: _curatorSubTabIndex == 1,
            onTap: () => setState(() => _curatorSubTabIndex = 1),
          ),
          span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
          _buildPlainTextTab(
            title: "wiki entities",
            isActive: _curatorSubTabIndex == 2,
            onTap: () => setState(() => _curatorSubTabIndex = 2),
          ),
          span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
          _buildPlainTextTab(
            title: "ai baseline",
            isActive: _curatorSubTabIndex == 3,
            onTap: () => setState(() => _curatorSubTabIndex = 3),
          ),
        ], classes: 'bg-white rounded-md p-4 shadow-sm', attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 8px; box-sizing: border-box; width: 100%;'});

      case 'settings':
        return div([
          _buildPlainTextTab(
            title: "toolbar buttons",
            isActive: _settingsSubTabIndex == 3,
            onTap: () => setState(() => _settingsSubTabIndex = 3),
          ),
          span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
          _buildPlainTextTab(
            title: "managed profiles",
            isActive: _settingsSubTabIndex == 1,
            onTap: () => setState(() => _settingsSubTabIndex = 1),
          ),
          if (isViewerAdmin) ...[
            span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
            _buildPlainTextTab(
              title: "shortcodes",
              isActive: _settingsSubTabIndex == 0,
              onTap: () => setState(() => _settingsSubTabIndex = 0),
            ),
            span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
            _buildPlainTextTab(
              title: "permissions",
              isActive: _settingsSubTabIndex == 2,
              onTap: () => setState(() => _settingsSubTabIndex = 2),
            ),
          ]
        ], classes: 'bg-white rounded-md p-4 shadow-sm', attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 8px; box-sizing: border-box; width: 100%;'});

      case 'collection':
      default:
        return div([], attributes: const {'style': 'display: none;'});
    }
  }

  Component _buildActiveTabContent(String tabName) {
    switch (tabName) {
      case 'maker':
        return _buildMakerTabContentBody();
      case 'index':
        return _buildIndexTabContentBody();
      case 'settings':
        return _buildSettingsTabContentBody();
      case 'curator':
        return _buildCuratorTabContentBody();
      case 'collection':
      default:
        return div([
          span([text('analytics')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 56px;'}),
          h3([text('${tabName.toUpperCase()} coming soon')], classes: 'font-bold text-black text-lg mt-4'),
          p([text('Archival features are currently being generated on our backend.')], classes: 'text-sm text-gray mt-2')
        ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }
  }

  Component _buildMakerTabContentBody() {
    return div([
      _buildWorksGridSchema(_showDrafts ? _draftWorks : _publishedWorks)
    ]);
  }

  Component _buildIndexTabContentBody() {
    return div([
      if (_indexSubTabIndex == 0)
        _buildWorksGridSchema(_userMentions)
      else
        _buildCommentsListSubView()
    ]);
  }

  Component _buildCuratorTabContentBody() {
    return div([
      if (_curatorSubTabIndex == 0)
        _buildWorksGridSchema(_userWorks.where((w) => w['sourceFile'] != null && w['isLive'] != true).toList())
      else if (_curatorSubTabIndex == 1)
        _buildWorksGridSchema(_userWorks.where((w) => w['sourceFile'] == null || w['isLive'] == true).toList())
      else if (_curatorSubTabIndex == 2)
          _buildCuratorEntitiesList()
        else
          _buildAITrainingDataPortal()
    ]);
  }

  Component _buildSettingsTabContentBody() {
    final bool isViewerAdmin = _viewerAccount?.role == 'admin' || (_viewerAccount?.roles.contains('admin') ?? false);
    return div([
      if (_settingsSubTabIndex == 3)
        _buildSocialButtonsSettingsView()
      else if (_settingsSubTabIndex == 1)
        _buildManagedProfilesSettingsView()
      else if (_settingsSubTabIndex == 0 && isViewerAdmin)
          _buildShortcodesSettingsView()
        else if (_settingsSubTabIndex == 2 && isViewerAdmin)
            _buildPermissionsSettingsView()
          else
            div([])
    ]);
  }

  Component _buildWorksGridSchema(List<Map<String, dynamic>> works) {
    if (works.isEmpty) {
      return div([
        span([text('library_books')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
        p([text('No items available in this category.')], classes: 'text-sm text-gray italic mt-4')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }

    return div([
      for (var w in works)
        _buildWorkGridTile(w)
    ], attributes: const {
      'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
    });
  }

  Component _buildWorkGridTile(Map<String, dynamic> w) {
    final String fanzineId = w['id'] ?? '';
    final String title = w['title'] ?? 'Untitled Fanzine';
    final String volume = w['volume'] ?? '';
    final String issue = w['issue'] ?? '';
    final String wholeNumber = w['wholeNumber'] ?? '';

    String displaySuffix = '';
    if (volume.isNotEmpty) displaySuffix += " Vol. $volume";
    if (issue.isNotEmpty) displaySuffix += " No. $issue";
    if (wholeNumber.isNotEmpty) displaySuffix += " ($wholeNumber)";

    final String coverUrl = w['gridCoverImage'] ?? (w['sourceFile'] != null
        ? 'https://placehold.co/450x720/png?text=Archival+Ingest'
        : 'https://placehold.co/450x720/png?text=Folio');

    // Route dynamically based on ownership and draft status
    final String activeTab = _visibleTabs.isNotEmpty ? _visibleTabs[_currentTabIndex] : 'maker';
    final bool isDraft = w['isLive'] != true;
    final bool canEdit = _isMe || (_viewerAccount?.role == 'admin') || (_viewerAccount?.role == 'moderator') || (_viewerAccount?.isCurator ?? false);

    // If this is an unsaved temporary folio, direct route through ShortLinkPage using its local code key
    final String codeKey = w['shortCode'] ?? fanzineId;
    final String targetRoute = (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId))
        ? '/$codeKey'
        : ((canEdit && (isDraft || _showDrafts || activeTab == 'curator'))
        ? '/editor/$fanzineId'
        : '/reader/$fanzineId');

    return a(
        [
          // Poster image
          div([
            // Status Tag
            div([text(w['type'] ?? 'ingested')], attributes: const {
              'style': 'position: absolute; top: 8px; left: 8px; background-color: rgba(0,0,0,0.7); color: white; padding: 2px 8px; border-radius: 4px; font-size: 8px; font-weight: bold; text-transform: uppercase;'
            })
          ], attributes: {
            'style': 'aspect-ratio: 5/8; background-color: #f3f4f6; background-image: url("$coverUrl"); background-size: cover; background-position: center; position: relative;'
          }),

          // Metadata footer
          div([
            span([text(title)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'}),
            if (displaySuffix.isNotEmpty)
              span([text(displaySuffix)], attributes: const {'style': 'font-size: 11px; color: #666;'})
          ], attributes: const {'style': 'padding: 12px; display: flex; flex-direction: column; gap: 4px;'})
        ],
        href: targetRoute,
        classes: 'bg-white rounded-lg shadow-sm overflow-hidden transition-all',
        attributes: const {
          'style': 'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer;'
        }
    );
  }

  Component _buildCommentsListSubView() {
    if (_userComments.isEmpty) {
      return div([
        span([text('chat_bubble')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
        p([text('No comments posted by this profile.')], classes: 'text-sm text-gray italic mt-4')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }

    return div([
      h2([text("COMMENTS POSTED")], classes: 'font-bold text-sm text-gray mb-4'),
      for (var c in _userComments)
        div([
          div([
            span([text(c['createdAt'] is DateTime ? (c['createdAt'] as DateTime).toIso8601String().split('T').first : '')]),
            if (c['context'] != null && c['context']['fanzineTitle'] != null)
              span([text("via ${c['context']['fanzineTitle']}")], attributes: const {'style': 'font-style: italic;'})
          ], attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between; font-size: 11px; color: #888; margin-bottom: 8px;'}),
          p([text(c['text'] ?? '')], attributes: const {'style': 'border-bottom: 1px solid #f0f0f0; padding-bottom: 16px; margin-bottom: 16px;'})
        ], attributes: const {'style': 'border-bottom: 1px solid #f0f0f0; padding-bottom: 16px; margin-bottom: 16px;'})
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  Component _buildCuratorEntitiesList() {
    final Map<String, int> entityCounts = {};
    for (var fz in _userWorks) {
      final List entities = fz['draftEntities'] ?? [];
      for (var ent in entities) {
        final name = ent.toString();
        entityCounts[name] = (entityCounts[name] ?? 0) + 1;
      }
    }

    if (entityCounts.isEmpty) {
      return div([
        p([text("No entities detected in draft curator pipeline.")], classes: 'text-sm text-gray italic')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }

    final sortedNames = entityCounts.keys.toList()..sort((a, b) => entityCounts[b]!.compareTo(entityCounts[a]!));

    return div([
      h2([text("DETECTED DRAFT ENTITIES")], classes: 'font-bold text-sm text-gray mb-4'),
      for (var name in sortedNames)
        div([
          span([text(name)], attributes: const {'style': 'font-weight: bold;'}),
          span([text('${entityCounts[name]} occurrences')], attributes: const {'style': 'color: #888; font-size: 11px;'})
        ], attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #eee; font-size: 13px;'})
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-3');
  }

  Component _buildAITrainingDataPortal() {
    final trainingItems = _aiTrainingData.where((img) {
      final int cScore = img['human_correction_score'] ?? 0;
      final int lScore = img['human_linking_score'] ?? 0;
      return cScore > 0 || lScore > 0;
    }).toList();

    if (trainingItems.isEmpty) {
      return div([
        p([text("No training data yet.")], classes: 'text-sm text-gray italic')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }

    return div([
      h2([text("AI REINFORCEMENT BASELINES")], classes: 'font-bold text-sm text-gray mb-2'),
      for (var item in trainingItems)
        div([
          if (item['gridUrl'] != null || item['fileUrl'] != null)
            img(src: item['gridUrl'] ?? item['fileUrl'], attributes: {'style': 'width: 48px; height: 48px; object-fit: cover; border-radius: 4px; border: 1px solid #ccc;'}),
          span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
          div([
            span([text(item['title'] ?? item['fileName'] ?? 'Archival Page')], attributes: const {'style': 'font-weight: bold;'}),
            span([
              text("Correction Score: ${item['human_correction_score'] ?? 0} | Link Score: ${item['human_linking_score'] ?? 0}")
            ], attributes: const {'style': 'font-size: 11px; color: #666;'})
          ], attributes: const {'style': 'display: flex; align-items: center; padding: 12px; border: 1px solid #eee; border-radius: 8px; font-size: 13px;'})
        ], attributes: const {'style': 'display: flex; align-items: center; padding: 12px; border: 1px solid #eee; border-radius: 8px; font-size: 13px;'})
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  Component _buildSocialButtonsSettingsView() {
    final togglableTools = ReaderToolsConfig.tools
        .where((t) => t.id != 'Settings' && t.role == ToolRole.public)
        .toList();

    return div([
      h2([text("CUSTOMIZE SOCIAL TOOLBAR BUTTONS")], classes: 'font-bold text-sm text-gray mb-4'),
      for (var tool in togglableTools)
        _buildToolbarButtonSettingsRow(tool)
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  Component _buildToolbarButtonSettingsRow(ReaderTool tool) {
    final bool isVisible = _socialButtonVisibility[tool.id] ?? true;
    final resolvedIcon = cleanIconName(tool.defaultIcon);

    return div([
      div([
        span([text(resolvedIcon)], classes: 'material-symbols-outlined text-gray-500', attributes: const {'style': 'font-size: 22px;'}),
        span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
        span([text(tool.label)], attributes: const {'style': 'font-size: 14px; font-weight: bold; color: black;'})
      ], attributes: const {'style': 'display: flex; align-items: center;'}),

      // iOS-style Toggle Switcher
      div([
        div([], attributes: {
          'style': 'width: 20px; height: 20px; border-radius: 50%; background-color: white; transition: left 0.25s; position: absolute; '
              'left: ${isVisible ? '22px' : '2px'};'
        })
      ], attributes: {
        'style': 'width: 44px; height: 24px; border-radius: 100px; padding: 2px; position: relative; transition: background 0.25s; cursor: pointer; '
            'background-color: ${isVisible ? '#6750A4' : '#ccc'};'
      })
    ], classes: 'hover:bg-gray-50 rounded-lg p-3 transition-all', attributes: const {
      'style': 'display: center; align-items: center; justify-content: space-between; border-bottom: 1px solid #f5f5f5; cursor: pointer;'
    }, events: {
      'click': (e) => _toggleSocialButtonVisibility(tool.id)
    });
  }

  Component _buildManagedProfilesSettingsView() {
    return div([
      // Create Managed Profile Card Form
      div([
        h3([text("Create Managed Identity (Human or Estate)")], classes: 'font-bold text-sm text-black'),
        div([
          input(attributes: {'placeholder': 'First Name', 'value': _newManagedFirstName}, events: {'input': (e) => setState(() => _newManagedFirstName = (e.target as dynamic).value)}),
          span([], attributes: const {'style': 'display: inline-block; width: 12px;'}),
          input(attributes: {'placeholder': 'Last Name', 'value': _newManagedLastName}, events: {'input': (e) => setState(() => _newManagedLastName = (e.target as dynamic).value)}),
        ], attributes: const {'style': 'display: flex; gap: 12px;'}),
        input(attributes: {'placeholder': 'Identity Biography / Historical Context', 'value': _newManagedBio}, events: {'input': (e) => setState(() => _newManagedBio = (e.target as dynamic).value)}),
        button(
            [text(_isCreatingManagedProfile ? "initializing..." : "create profile")],
            classes: 'btn-primary nav-pill',
            attributes: _isCreatingManagedProfile
                ? const {'disabled': 'true', 'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; width: 180px;'}
                : const {'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; width: 180px;'},
            events: {'click': (e) => _createManagedProfile()}
        )
      ], attributes: const {'style': 'border: 1px dashed #ccc; padding: 20px; border-radius: 8px; background-color: #fcfcfc; display: flex; flex-direction: column; gap: 12px;'}),

      // List of Active Managed Profiles
      if (_allManagedProfiles.isNotEmpty) ...[
        div([], attributes: const {'style': 'height: 24px;'}),
        h3([text("PROFILES CURRENTLY UNDER YOUR MANAGEMENT")], classes: 'font-bold text-xs text-gray mt-4'),
        div([], attributes: const {'style': 'height: 8px;'}),
        div([
          for (var p in _allManagedProfiles)
            a([
              span([text(p['displayName'] ?? '')], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black;'}),
              span([text('@${p['username']}')], attributes: const {'style': 'font-size: 11px; color: #666; margin-top: 4px;'})
            ], href: '/${p['username']}', classes: 'bg-gray-50 hover:bg-gray-100 rounded-md p-4 transition-all', attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #eee; cursor: pointer;'})
        ], attributes: const {
          'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px;'
        })
      ]
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-6');
  }

  Component _buildShortcodesSettingsView() {
    return div([
      h2([text("GLOBAL CONGESTION ROUTING SHORTCODES")], classes: 'font-bold text-sm text-gray mb-4'),
      p([
        text("Configure the default shortcode bindings representing the Global 'Book of the Week' presented to guests on sign in or registration workflows.")
      ], classes: 'text-xs text-gray italic leading-relaxed'),
      div([], attributes: const {'style': 'height: 12px;'}),

      div([
        span([text("LOGIN STICKER SHORTCODE")], classes: 'text-xs font-bold text-gray'),
        input(attributes: {'value': _loginZineShortcode}, events: {'input': (e) => _loginZineShortcode = (e.target as dynamic).value})
      ], classes: 'flex-col gap-2'),

      div([
        span([text("REGISTRATION STICKER SHORTCODE")], classes: 'text-xs font-bold text-gray'),
        input(attributes: {'value': _registerZineShortcode}, events: {'input': (e) => _registerZineShortcode = (e.target as dynamic).value})
      ], classes: 'flex-col gap-2'),

      div([], attributes: const {'style': 'height: 12px;'}),
      button(
          [text(_isSavingSettings ? "saving..." : "save settings")],
          classes: 'btn-primary nav-pill',
          attributes: _isSavingSettings
              ? const {'disabled': 'true', 'style': 'height: 38px; display: inline-flex; align-items: center; justify-content: center; width: 160px;'}
              : const {'style': 'height: 38px; display: inline-flex; align-items: center; justify-content: center; width: 160px;'},
          events: {'click': (e) => _saveGlobalSettings()}
      )
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  Component _buildPermissionsSettingsView() {
    if (_allSystemUsers.isEmpty) {
      return div([
        p([text('No registered Users loaded.')], classes: 'text-sm text-gray italic')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }

    return div([
      h2([text("SYSTEM LEVEL ROLES & ACCESS GRANTS")], classes: 'font-bold text-sm text-gray mb-4'),
      for (var u in _allSystemUsers)
        _buildUserPermissionManagerRow(u)
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  Component _buildUserPermissionManagerRow(Map<String, dynamic> u) {
    final String uid = u['uid'] ?? u['id'] ?? '';
    final String email = u['email'] ?? 'guest';
    final String currentRole = u['role'] ?? 'user';

    return div([
      div([
        span([text(email)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black;'}),
        span([text("UID: $uid")], attributes: const {'style': 'font-size: 10px; color: #888; font-family: monospace;'})
      ], classes: 'flex-col gap-1'),

      div([
        _buildRoleBadgeSelector(uid, "admin", currentRole),
        span([], attributes: const {'style': 'display: inline-block; width: 8px;'}),
        _buildRoleBadgeSelector(uid, "moderator", currentRole),
        span([], attributes: const {'style': 'display: inline-block; width: 8px;'}),
        _buildRoleBadgeSelector(uid, "curator", currentRole),
        span([], attributes: const {'style': 'display: inline-block; width: 8px;'}),
        _buildRoleBadgeSelector(uid, "user", currentRole)
      ], attributes: const {'style': 'display: flex; gap: 8px;'})
    ], classes: 'bg-gray-50 rounded-lg p-4 border border-gray-100 flex-row justify-between items-center', attributes: const {'style': 'display: flex; flex-wrap: wrap; gap: 16px;'});
  }

  Component _buildRoleBadgeSelector(String uid, String role, String activeRole) {
    final bool isSelected = activeRole == role;

    return button(
        [text(role)],
        classes: isSelected ? 'active m3-chip' : 'm3-chip',
        attributes: const {'style': 'height: 28px; padding: 0 10px; font-size: 10px; font-weight: bold; border-radius: 50px; cursor: pointer; border: none; text-transform: uppercase;'},
        events: {
          'click': (e) => _updateUserPermission(uid, role)
        }
    );
  }

  Component _buildMakerModalOverlay() {
    final bool isUploadMode = _makerModalMode == 'upload';

    return div(
        classes: 'global-modal-overlay',
        attributes: const {
          'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(6px);'
        },
        [
          if (!isUploadMode)
          // Options Mode: Keep the beautiful classic Manila Envelope modal box
            div(
                classes: 'manila-envelope',
                attributes: const {
                  'style': 'max-width: 420px; max-height: 580px; border-radius: 12px; overflow: hidden; position: relative;'
                },
                [
                  button(
                      classes: 'modal-close-btn',
                      attributes: const {
                        'style': 'position: absolute; top: 12px; right: 12px; border: none; background: rgba(255,255,255,0.8); border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 16px; font-weight: bold; z-index: 200;'
                      },
                      events: {
                        'click': (e) {
                          _showMakerModal = false;
                        }
                      },
                      [text('×')]
                  ),
                  _buildMakerOptionsContent()
                ]
            )
          else
          // Upload Mode: Full scrollable single-item list layout container
            div(
                classes: 'upload-list-wrapper',
                attributes: const {
                  'style': 'width: 100%; max-width: 500px; max-height: 90vh; display: flex; flex-direction: column; gap: 16px; box-sizing: border-box; padding: 16px; position: relative; overflow-y: auto;'
                },
                [
                  // Floating close button at the top-right of the scroll area
                  button(
                      classes: 'modal-close-btn',
                      attributes: const {
                        'style': 'position: absolute; top: 24px; right: 24px; border: none; background: rgba(255,255,255,0.9); border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 16px; font-weight: bold; z-index: 1000;'
                      },
                      events: {
                        'click': (e) {
                          _showMakerModal = false;
                        }
                      },
                      [text('×')]
                  ),
                  _buildMakerUploadContent()
                ]
            )
        ]
    );
  }

  Component _buildMakerOptionsContent() {
    return div(classes: 'white-sticker p-6 w-full h-full flex flex-col justify-center items-center', [
      h1(classes: 'font-bold text-lg text-center mb-6', [text('maker options')]),

      button(
          [text("single image")],
          classes: 'profile-btn mb-4',
          attributes: const {'style': 'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-transform: uppercase; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer;'},
          events: {
            'click': (e) => setState(() {
              _makerModalMode = 'upload';
              _uploadError = null;
            })
          }
      ),

      button(
          [text("folio")],
          classes: 'profile-btn mb-4',
          attributes: const {'style': 'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-transform: uppercase; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer;'},
          events: {
            'click': (e) => _createFolio()
          }
      ),

      button(
          [text("calendar")],
          classes: 'profile-btn mb-4',
          attributes: const {'style': 'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-transform: uppercase; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer;'},
          events: {
            'click': (e) => _createCalendar()
          }
      ),
    ]);
  }

  Component _buildUploadToolbarButton(String label, String iconName, bool isActive) {
    final btnClasses = 'toolbar-btn ${isActive ? 'active' : ''}';
    return button(
        classes: btnClasses,
        events: const {},
        [
          div(classes: 'toolbar-icon-wrapper', attributes: const {'style': 'padding: 8px; border-radius: 50%; border: 2px solid black; display: flex; justify-content: center; align-items: center; margin-bottom: 4px; pointer-events: none;'}, [
            span(
                classes: 'material-symbols-outlined',
                attributes: {
                  'style': isActive ? "font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; color: #6750A4;" : "font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24; color: #ccc;"
                },
                [text(iconName)]
            )
          ]),
          span(classes: 'toolbar-label', attributes: {
            'style': 'color: ${isActive ? '#6750a4' : '#ccc'}; font-weight: ${isActive ? 'bold' : 'normal'}; font-size: 10px;'
          }, [text(label)])
        ]
    );
  }

  /// First Cell Header: Manila Envelope containing our visual upload metadata actions
  Component _buildUploadHeaderWidget() {
    return div(
        classes: 'manila-envelope w-full mb-4',
        attributes: const {
          'style': 'border-radius: 8px; padding: 16px; width: 100%; box-sizing: border-box; display: flex; flex-direction: column; justify-content: center; align-items: center; aspect-ratio: 5 / 8;'
        },
        [
          div(
              classes: 'white-sticker',
              attributes: const {
                'style': 'width: 90%; height: 85%; padding: 20px; display: flex; flex-direction: column; justify-content: space-between; align-items: center; border-radius: 8px;'
              },
              [
                // Top Title Context
                div([
                  h1(classes: 'font-bold text-base text-center mb-1', attributes: const {'style': 'color: black; margin: 0; font-size: 16px;'}, [text('upload single image')]),
                  p(classes: 'text-xs text-center text-gray', attributes: const {'style': 'margin: 0; color: #666; font-size: 11px;'}, [text('Maker Pipeline')])
                ]),

                // Centered Identity Gif
                img(
                    src: 'assets/logo200.gif',
                    attributes: const {
                      'style': 'width: 70px; height: auto; display: block; margin: 12px 0;'
                    }
                ),

                // Native Envelope Action controls (Back / Publish)
                div(classes: 'flex-col w-full gap-2', attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'}, [
                  button(
                      [text(_isUploadingImage ? "publishing..." : "publish")],
                      classes: 'btn-primary',
                      attributes: _isUploadingImage
                          ? const {'disabled': 'true', 'style': 'padding: 10px; border-radius: 8px; font-weight: bold; width: 100%;'}
                          : const {'style': 'padding: 10px; border-radius: 8px; font-weight: bold; width: 100%; background-color: #6750A4; color: white;'},
                      events: {
                        'click': (e) => _submitSingleImage()
                      }
                  ),
                  button(
                      [text("back")],
                      classes: 'profile-btn',
                      attributes: const {'style': 'width: 100%; padding: 8px; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 8px; background: white; color: black; cursor: pointer;'},
                      events: {'click': (e) => setState(() {
                        _makerModalMode = 'options';
                        _uploadImageBase64 = null;
                        _uploadImageName = null;
                        _uploadPreviewUrl = null;
                        _uploadCreators = [];
                      })}
                  )
                ])
              ]
          )
        ]
    );
  }

  /// Second Cell: Strictly 5:8 Image frame and standard social buttons underneath
  Component _buildUploadPageItemWidget() {
    return div(
        classes: 'reader-list-item flex-col w-full bg-white rounded-lg overflow-hidden',
        attributes: const {
          'style': 'display: flex; flex-direction: column; width: 100%; box-sizing: border-box; border: 1px solid #eee; background-color: white; border-radius: 8px;'
        },
        [
          // 1. The 5:8 Preview Sheet Container (Visual parity with ReaderPageItem)
          div(
              classes: 'aspect-5-8 bg-gray-100 flex-col items-center justify-center relative',
              attributes: const {
                'style': 'width: 100%; aspect-ratio: 5 / 8; background-color: #f5f5f5; display: flex; flex-direction: column; align-items: center; justify-content: center; position: relative; cursor: pointer;'
              },
              events: {
                'click': (e) {
                  _pickAndPreviewImage();
                }
              },
              [
                if (_uploadPreviewUrl != null)
                  img(
                      src: _uploadPreviewUrl!,
                      attributes: const {
                        'style': 'width: 100%; height: 100%; object-fit: contain; position: absolute; top: 0; left: 0;'
                      }
                  )
                else
                  div(
                      classes: 'flex flex-col items-center justify-center p-4 text-gray-400',
                      [
                        span([text('add_photo_alternate')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 48px; margin-bottom: 8px; color: #aaa;'}),
                        span([text('Click to select image')], attributes: const {'style': 'font-size: 12px; font-weight: 500; text-transform: lowercase; color: #666;'})
                      ]
                  ),

                // Invisible, absolute-positioned native file input covering the entire box
                input(
                    id: 'maker-upload-picker',
                    classes: 'maker-upload-file-input',
                    attributes: const {
                      'type': 'file',
                      'accept': 'image/*',
                      'style': 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; opacity: 0; cursor: pointer; z-index: 10;'
                    },
                    events: {
                      'change': (e) {
                        _onFileInputChanged();
                      },
                      'click': (e) {
                        // Prevent bubble up so it doesn't trigger parent click twice
                        (e as dynamic).stopPropagation();
                      }
                    }
                )
              ]
          ),

          // 2. Custom Toolbar (Unifies read/create layouts) with "Upload" pre-selected and highlighted on load
          div(classes: 'toolbar-container w-full border-t border-b border-gray-100 py-2 my-1', attributes: const {
            'style': 'display: flex; justify-content: center; gap: 12px; box-sizing: border-box; width: 100%; background: #fff;'
          }, [
            _buildUploadToolbarButton('upload', 'edit_document', true),
            _buildUploadToolbarButton('like', 'favorite_border', false),
            _buildUploadToolbarButton('comments', 'chat_bubble_outline', false),
            _buildUploadToolbarButton('tags', 'tag', false),
          ]),

          // 3. Active Metadata Panel (Sliding Form Drawer)
          div(
              classes: 'p-4 mt-1 panel-container-animate',
              attributes: const {
                'style': 'background-color: #ffffff; border-top: 1px solid #eee; width: 100%; box-sizing: border-box; text-align: left;'
              },
              [
                div(classes: 'flex-col', [
                  div(classes: 'mb-4', [
                    span(
                        classes: 'text-xs font-bold text-gray',
                        attributes: const {'style': 'letter-spacing: 1px; text-transform: uppercase; color: #666; font-size: 11px;'},
                        [text("UPLOAD METADATA")]
                    )
                  ]),

                  // Text Fields
                  input(
                    attributes: const {'type': 'text', 'placeholder': 'Title', 'style': 'margin-bottom: 10px; border-radius: 8px; padding: 12px; border: 1px solid #ccc; font-size: 14px;'},
                    events: {'input': (e) => _uploadTitle = (e.target as dynamic).value},
                  ),
                  input(
                    attributes: const {'type': 'text', 'placeholder': 'Caption / Description (optional)', 'style': 'margin-bottom: 10px; border-radius: 8px; padding: 12px; border: 1px solid #ccc; font-size: 14px;'},
                    events: {'input': (e) => _uploadDescription = (e.target as dynamic).value},
                  ),
                  input(
                    attributes: const {'type': 'text', 'placeholder': 'Indicia / Copyright (optional)', 'style': 'margin-bottom: 12px; border-radius: 8px; padding: 12px; border: 1px solid #ccc; font-size: 14px;'},
                    events: {'input': (e) => _uploadIndicia = (e.target as dynamic).value},
                  ),

                  // Creators Section
                  div(
                      classes: 'w-full text-left flex flex-col',
                      attributes: const {'style': 'margin-top: 8px; margin-bottom: 16px;'},
                      [
                        span([text('Creators')], attributes: const {'style': 'font-size: 12px; font-weight: bold; color: #333; margin-bottom: 6px;'}),

                        if (_uploadCreators.isNotEmpty)
                          div(
                              classes: 'flex flex-col gap-1 w-full mb-2',
                              [
                                for (int i = 0; i < _uploadCreators.length; i++)
                                  div(
                                      classes: 'flex flex-row items-center justify-between bg-gray-50 border border-gray-150 p-1.5 rounded',
                                      attributes: const {'style': 'font-size: 11px; font-weight: 500; margin-bottom: 3px;'},
                                      [
                                        span([text('${_uploadCreators[i]['name']} (${_uploadCreators[i]['role']})')]),
                                        span(
                                            classes: 'material-symbols-outlined text-red-500 cursor-pointer',
                                            attributes: const {'style': 'font-size: 16px; margin-left: 6px;'},
                                            events: {
                                              'click': (e) => setState(() {
                                                _uploadCreators.removeAt(i);
                                              })
                                            },
                                            [text('remove_circle')]
                                        )
                                      ]
                                  )
                              ]
                          ),

                        div(
                            classes: 'flex flex-row items-center gap-2 w-full',
                            attributes: const {'style': 'box-sizing: border-box;'},
                            [
                              div(
                                  classes: 'flex-1',
                                  [
                                    input(
                                      attributes: {
                                        'type': 'text',
                                        'placeholder': '@handle',
                                        'value': _newCreatorHandle,
                                        'style': 'margin-bottom: 0; padding: 6px 10px; font-size: 12px; box-sizing: border-box; border-radius: 6px; border: 1px solid #ccc;'
                                      },
                                      events: {'input': (e) => _newCreatorHandle = (e.target as dynamic).value},
                                    )
                                  ]
                              ),
                              div(
                                  classes: 'flex-1',
                                  [
                                    input(
                                      attributes: {
                                        'type': 'text',
                                        'placeholder': 'Role',
                                        'value': _newCreatorRole,
                                        'style': 'margin-bottom: 0; padding: 6px 10px; font-size: 12px; box-sizing: border-box; border-radius: 6px; border: 1px solid #ccc;'
                                      },
                                      events: {'input': (e) => _newCreatorRole = (e.target as dynamic).value},
                                    )
                                  ]
                              ),
                              span(
                                  classes: 'material-symbols-outlined text-green-600 cursor-pointer',
                                  attributes: const {'style': 'font-size: 22px; padding: 2px;'},
                                  events: {
                                    'click': (e) => _addCreator()
                                  },
                                  [text('add_circle')]
                              )
                            ]
                        )
                      ]
                  )
                ])
              ]
          )
        ]
    );
  }

  // Visual Image Upload sticker that coordinates the structural list sections
  Component _buildMakerUploadContent() {
    return div(
        classes: 'flex-col w-full',
        attributes: const {
          'style': 'display: flex; flex-direction: column; width: 100%; gap: 16px; box-sizing: border-box;'
        },
        [
          _buildUploadHeaderWidget(),
          _buildUploadPageItemWidget(),
        ]
    );
  }
}