import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/server_firestore_client.dart';
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
  }

  @override
  void didUpdateComponent(ShortLinkPage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.code != component.code && kIsWeb) {
      print('[SHORTLINK STATE] Code changed to "${component.code}". Re-triggering resolution.');
      _resolveOnClient();
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

      return FanzineReaderPage(
        fanzineId: _targetFanzineId!,
        initialPageNumber: initialPage,
        preloadedFanzine: _fanzineData,
        preloadedPages: _pagesData,
        preloadedCreatorProfiles: _creatorProfiles,
        preloadedImageStats: _imageStats,
        authState: component.authState,
        authBloc: component.authBloc,
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