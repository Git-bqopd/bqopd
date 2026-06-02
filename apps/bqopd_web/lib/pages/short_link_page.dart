import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/server_firestore_client.dart';
import '../utils/unsaved_fanzine_registry.dart';
import 'fanzine_reader_page.dart';
import 'profile_page.dart';

/// Resolved and pre-rendered matching view utilizing server pre-fetched payloads.
class ShortLinkPage extends StatefulComponent {
  final String code;
  final String? pageNumber;
  final AuthState? authState;
  final AuthBloc? authBloc;
  final IUserRepository userRepository;
  final IEngagementRepository engagementRepository;

  const ShortLinkPage({
    required this.code,
    this.pageNumber,
    required this.authState,
    required this.authBloc,
    required this.userRepository,
    required this.engagementRepository,
  });

  @override
  State<ShortLinkPage> createState() => _ShortLinkPageState();
}

class _ShortLinkPageState extends State<ShortLinkPage>
    with PreloadStateMixin, SyncStateMixin<ShortLinkPage, String> {
  String _preloadedJson = '{}';

  Map<String, dynamic> get _preloadedData {
    try {
      return jsonDecode(_preloadedJson) as Map<String, dynamic>;
    } catch (e) {
      print('[SHORTLINK STATE] Exception decoding preloaded state JSON: $e');
      return {};
    }
  }

  bool _isResolved = false;
  String _status = "Resolving link...";
  String? _targetFanzineId;
  String? _targetUserId;
  Map<String, dynamic>? _fanzineData;
  List<Map<String, dynamic>> _pagesData = [];
  Map<String, Map<String, dynamic>> _creatorProfiles = {};
  Map<String, Map<String, dynamic>> _imageStats = {};

  // Real-time account listener to determine active viewer permissions
  UserAccount? _viewerAccount;
  StreamSubscription? _accountSub;

  @override
  Future<void> preloadState() async {
    print('[SHORTLINK STATE] preloadState starting on server for code: "${component.code}"');
    try {
      final payload = await ServerFirestoreClient.resolveFullPayload(component.code);
      _preloadedJson = jsonEncode(payload);

      if (!kIsWeb) {
        print('[SHORTLINK STATE] Preloading active on server. Injecting raw HTML state immediately.');
        _applyPayload(payload);
      }
    } catch (e, stack) {
      print('[SHORTLINK STATE EXCEPTION] PreloadState server loop failed: $e\n$stack');
    }
  }

  @override
  String getState() => _preloadedJson;

  @override
  void updateState(String value) {
    print('[SHORTLINK STATE] updateState called on client during hydration phase.');
    _preloadedJson = value;
  }

  @override
  void initState() {
    super.initState();
    final data = _preloadedData;
    if (data.isNotEmpty) {
      print('[SHORTLINK STATE] Successfully read preloaded server state in client. Instantly hydrating widgets.');
      _applyPayload(data);
    } else if (kIsWeb) {
      print('[SHORTLINK STATE WARNING] Preloaded server state was completely EMPTY in client. Hydrating fallback resolver.');
      _resolveOnClient();
    }
    _listenToViewerAccount();
  }

  @override
  void didUpdateComponent(ShortLinkPage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.code != component.code && kIsWeb) {
      print('[SHORTLINK STATE] Code changed to "${component.code}". Re-triggering resolution.');
      _resolveOnClient();
    }
    if (oldComponent.authState?.user?.uid != component.authState?.user?.uid && kIsWeb) {
      _listenToViewerAccount();
    }
  }

  @override
  void dispose() {
    _accountSub?.cancel();
    super.dispose();
  }

  void _listenToViewerAccount() {
    _accountSub?.cancel();
    _accountSub = null;
    if (kIsWeb) {
      final uid = component.authState?.user?.uid ?? getCurrentUserId();
      if (uid != null) {
        _accountSub = component.userRepository.watchUserAccount(uid).listen((account) {
          if (mounted) {
            setState(() {
              _viewerAccount = account;
            });
          }
        });
      }
    }
  }

  void _applyPayload(Map<String, dynamic> data) {
    _status = data['status'] ?? '';
    _targetFanzineId = data['targetFanzineId'];
    _targetUserId = data['targetUserId'];
    _fanzineData = data['fanzineData'];
    if (data['pages'] != null) {
      _pagesData = List<Map<String, dynamic>>.from(data['pages']);
    }
    if (data['creatorProfiles'] != null) {
      _creatorProfiles = Map<String, Map<String, dynamic>>.from(
        (data['creatorProfiles'] as Map).map(
              (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
        ),
      );
    }
    if (data['imageStats'] != null) {
      _imageStats = Map<String, Map<String, dynamic>>.from(
        (data['imageStats'] as Map).map(
              (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
        ),
      );
    }
    _isResolved = true;
    print('[SHORTLINK STATE] Payload applied successfully. Mapped Fanzine ID: "$_targetFanzineId" | Mapped User ID: "$_targetUserId"');
  }

  /// Client-side fallback routine if the component loads without a preloaded state chunk.
  Future<void> _resolveOnClient() async {
    if (!mounted) return;
    setState(() {
      _status = "Resolving link...";
      _isResolved = false;
    });

    try {
      final payload = await ServerFirestoreClient.resolveFullPayload(component.code);
      if (mounted) {
        setState(() {
          _applyPayload(payload);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Error resolving link: $e";
          _isResolved = true;
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    print('[SHORTLINK RENDER] Render loop called. Mapped Fanzine: "$_targetFanzineId" | Status: "$_status"');
    if (!_isResolved) {
      return div(
          classes: 'flex-col items-center justify-center w-full',
          attributes: {'style': 'min-height: 100vh;'},
          [div(classes: 'text-lg font-bold', [text(_status)])]);
    }

    if (_targetFanzineId != null) {
      final initialPage = component.pageNumber != null ? int.tryParse(component.pageNumber!) : null;

      // Auto-detect if this is a temporary, unsaved fanzine from our memory layer
      final bool isUnsavedTemp = UnsavedFanzineRegistry.fanzines.containsKey(_targetFanzineId);

      // Determine editing permissions
      final currentUid = component.authState?.user?.uid ?? getCurrentUserId();
      final ownerId = _fanzineData?['ownerId'] ?? _fanzineData?['editorId'] ?? '';
      final editors = (_fanzineData?['editors'] as List?)?.map((e) => e.toString()).toList() ?? [];

      final bool isOwnerOrEditor = currentUid != null && (currentUid == ownerId || editors.contains(currentUid));
      final bool isViewerAdmin = _viewerAccount?.role == 'admin' || (_viewerAccount?.roles.contains('admin') ?? false);
      final bool isViewerModerator = _viewerAccount?.role == 'moderator' || (_viewerAccount?.roles.contains('moderator') ?? false);
      final bool isViewerCurator = _viewerAccount?.role == 'curator' || (_viewerAccount?.roles.contains('curator') ?? false) || (_viewerAccount?.isCurator ?? false);

      final bool canEdit = isOwnerOrEditor || isViewerAdmin || isViewerModerator || isViewerCurator;
      final bool isDraft = _fanzineData?['isLive'] != true;

      // Automatically launch directly into edit mode if they are authorized and the fanzine is currently a draft/folio
      final bool shouldEdit = isUnsavedTemp || (canEdit && isDraft);

      return FanzineReaderPage(
        fanzineId: _targetFanzineId!,
        initialPageNumber: initialPage,
        preloadedFanzine: _fanzineData,
        preloadedPages: _pagesData,
        preloadedCreatorProfiles: _creatorProfiles,
        preloadedImageStats: _imageStats,
        authState: component.authState,
        authBloc: component.authBloc,
        isEditingMode: shouldEdit, // Auto-launch directly into the Editor for temporary creations or owner draft works!
      );
    }

    if (_targetUserId != null && component.authBloc != null) {
      return ProfilePage(
        authState: component.authState,
        authBloc: component.authBloc!,
        userRepository: component.userRepository,
        engagementRepository: component.engagementRepository,
        userId: _targetUserId,
      );
    }

    return div(
        classes: 'flex-col items-center justify-center w-full',
        attributes: {'style': 'min-height: 100vh;'},
        [
          p(classes: 'text-lg font-bold', [text(_status)]),
          a(href: '/', [text('Go Home')])
        ]);
  }
}