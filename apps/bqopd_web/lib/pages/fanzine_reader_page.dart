import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../components/fanzine_header.dart';
import '../components/fanzine_editor.dart';
import '../components/fanzine_layout.dart';

/// Jaspr Web Reader Page utilizing Set-based likedImageIds to optimize performance.
class FanzineReaderPage extends StatefulComponent {
  final String fanzineId;
  final int? initialPageNumber;
  final Map<String, dynamic>? preloadedFanzine;
  final List<Map<String, dynamic>>? preloadedPages;
  final Map<String, Map<String, dynamic>>? preloadedCreatorProfiles;
  final Map<String, Map<String, dynamic>>? preloadedImageStats;
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool isEditingMode;

  const FanzineReaderPage({
    required this.fanzineId,
    this.initialPageNumber,
    this.preloadedFanzine,
    this.preloadedPages,
    this.preloadedCreatorProfiles,
    this.preloadedImageStats,
    this.authState,
    this.authBloc,
    this.isEditingMode = false,
    super.key,
  });

  @override
  State<FanzineReaderPage> createState() => _FanzineReaderPageState();
}

class _FanzineReaderPageState extends State<FanzineReaderPage> {
  Map<String, dynamic>? _fanzine;
  List<Map<String, dynamic>> _pages = [];
  Map<String, Map<String, dynamic>> _creatorProfiles = {};
  Map<String, Map<String, dynamic>> _imageStats = {};
  bool _loading = true;

  // HIGH-PERFORMANCE CENTRALIZED STATE
  Set<String> _likedImageIds = {};
  dynamic _likesUnsub;

  @override
  void initState() {
    super.initState();
    if (component.preloadedFanzine != null && component.preloadedPages != null) {
      _fanzine = component.preloadedFanzine;
      _pages = component.preloadedPages!;
      _creatorProfiles = component.preloadedCreatorProfiles ?? {};
      _imageStats = component.preloadedImageStats ?? {};
      _loading = false;
    } else if (kIsWeb) {
      _loadData();
    }
    _setupLikesPipeline();
  }

  void _setupLikesPipeline() {
    if (kIsWeb) {
      // Establish initial listener
      _listenToUserLikes();

      // Refresh unified channel immediately on login/logout changes
      onAuthStateChangedListener((uid, email) {
        _listenToUserLikes();
      });
    }
  }

  void _listenToUserLikes() {
    _likesUnsub?.callAsFunction();
    _likesUnsub = null;

    final uid = getCurrentUserId();
    if (uid == null) {
      if (mounted) setState(() => _likedImageIds = {});
      return;
    }

    _likesUnsub = fsListenQuery('Users/$uid/activity/likes/images', '', '', '', '', false, (jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final Set<String> likedIds = decoded.map((d) {
          final data = d['data'] as Map<String, dynamic>? ?? {};
          return data['imageId']?.toString() ?? d['id']?.toString() ?? '';
        }).where((id) => id.isNotEmpty).toSet();

        if (mounted) {
          setState(() {
            _likedImageIds = likedIds;
          });
        }
      } catch (e) {
        print("Error parsing unified likes structure: $e");
      }
    });
  }

  @override
  void dispose() {
    _likesUnsub?.callAsFunction();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final fzRes = await fsGetDoc('fanzines/${component.fanzineId}');
      final fzDoc = jsonDecode(fzRes);

      if (fzDoc['exists']) {
        _fanzine = fzDoc['data'];

        final pagesRes = await fsQuery('fanzines/${component.fanzineId}/pages', '', '', '', 'pageNumber');
        final List pagesList = jsonDecode(pagesRes);
        _pages = pagesList.map((p) {
          final data = p['data'] as Map<String, dynamic>;
          data['__id'] = p['id'];
          return data;
        }).toList();

        final creators = _fanzine!['masterCreators'] as List? ?? [];
        final Map<String, Map<String, dynamic>> profiles = {};
        final Map<String, Map<String, dynamic>> stats = {};

        final Set<String> uidsToFetch = creators
            .map((c) => c['uid'] as String?)
            .where((uid) => uid != null && uid.isNotEmpty)
            .cast<String>()
            .toSet();

        final List<Future<void>> parallelFetches = [];

        // Concurrently load creator profiles
        for (final uid in uidsToFetch) {
          parallelFetches.add(
            fsGetDoc('profiles/$uid').then((pRes) {
              final pDoc = jsonDecode(pRes);
              if (pDoc['exists']) profiles[uid] = pDoc['data'];
            }),
          );
        }

        // Concurrently load image metadata
        for (final page in _pages) {
          final imageId = page['imageId'] as String?;
          if (imageId != null && imageId.isNotEmpty) {
            parallelFetches.add(
              fsGetDoc('images/$imageId').then((imgRes) {
                final imgDoc = jsonDecode(imgRes);
                if (imgDoc['exists']) {
                  stats[imageId] = imgDoc['data'];
                }
              }),
            );
          }
        }

        await Future.wait(parallelFetches);

        _creatorProfiles = profiles;
        _imageStats = stats;
      }
    } catch (e) {
      print("Error loading fanzine: $e");
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
          classes: 'flex-col items-center justify-center w-full',
          attributes: {'style': 'min-height: 100vh;'},
          [p([text('Loading fanzine...')])]);
    }

    if (_fanzine == null) {
      return div(
          classes: 'flex-col items-center justify-center w-full',
          attributes: {'style': 'min-height: 100vh;'},
          [
            p([text('Fanzine not found.')]),
            a(href: '/', [text('Go Home')])
          ]);
    }

    // Tabbed Editor workspace used strictly at the top of the List view
    final Component listHeader = component.isEditingMode
        ? FanzineEditor(
      fanzineId: component.fanzineId,
      shortCode: _fanzine!['shortCode'],
      fanzineData: _fanzine,
      creatorProfiles: _creatorProfiles,
      imageStats: _imageStats,
      pageStructure: _pages,
      authState: component.authState,
      authBloc: component.authBloc,
    )
        : FanzineHeader(
      fanzineId: component.fanzineId,
      shortCode: _fanzine!['shortCode'],
      fanzineData: _fanzine,
      creatorProfiles: _creatorProfiles,
      imageStats: _imageStats,
      pageStructure: _pages,
      authState: component.authState,
      authBloc: component.authBloc,
    );

    // Compact sticker logo used at the top of the Grid view (forced to sticker only in editor mode)
    final Component gridHeader = FanzineHeader(
      fanzineId: component.fanzineId,
      shortCode: _fanzine!['shortCode'],
      fanzineData: _fanzine,
      creatorProfiles: _creatorProfiles,
      imageStats: _imageStats,
      pageStructure: _pages,
      isStickerOnly: component.isEditingMode,
      authState: component.authState,
      authBloc: component.authBloc,
    );

    return div(classes: 'w-full h-full', [
      FanzineLayout(
        fanzineId: component.fanzineId,
        pages: _pages,
        hasCover: _fanzine!['hasCover'] ?? true,
        initialPageNumber: component.initialPageNumber,
        preloadedImageStats: _imageStats,
        likedImageIds: _likedImageIds, // Pass liked Set down
        authState: component.authState,
        authBloc: component.authBloc,
        isEditingMode: component.isEditingMode,
        gridHeader: gridHeader,
        listHeader: listHeader,
      )
    ]);
  }
}