import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/unsaved_fanzine_registry.dart';
import '../components/fanzine_header.dart';
import '../components/fanzine_editor.dart';
import '../components/fanzine_curator.dart'; // Import newly created FanzineCurator
import '../components/fanzine_layout.dart';
import '../utils/firebase_mocks.dart';
import '../utils/web_utils.dart';

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
  Set<String> _likedImageIds = {};
  dynamic _likesUnsub;
  dynamic _fanzineUnsub;
  dynamic _pagesUnsub;
  bool? _overriddenTwoPage;

  @override
  void initState() {
    super.initState();
    if (component.preloadedFanzine != null && component.preloadedPages != null) {
      _fanzine = component.preloadedFanzine;
      _pages = component.preloadedPages!;
      _creatorProfiles = component.preloadedCreatorProfiles ?? {};
      _imageStats = component.preloadedImageStats ?? {};
      _loading = false;
      if (kIsWeb) {
        final shortCode = _fanzine?['shortCode'];
        if (shortCode != null && shortCode.toString().isNotEmpty) {
          redirectFanzinePath(context, shortCode.toString());
        }
        _listenToFanzineDoc();
        _listenToPagesDoc();
      }
    } else if (kIsWeb) {
      _loadData();
      _listenToFanzineDoc();
      _listenToPagesDoc();
    }
    _setupLikesPipeline();
  }

  void _setupLikesPipeline() {
    if (kIsWeb) {
      _listenToUserLikes();
      onAuthStateChangedListener((uid, email) {
        _listenToUserLikes();
      });
    }
  }

  void _cancelSubscription(dynamic unsub) {
    if (unsub == null) return;
    if (unsub is StreamSubscription) {
      unsub.cancel();
    } else if (unsub is FirebaseSubscription) {
      unsub.callAsFunction();
    }
  }

  void _listenToUserLikes() {
    _cancelSubscription(_likesUnsub);
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

  void _listenToFanzineDoc() {
    _cancelSubscription(_fanzineUnsub);
    _fanzineUnsub = null;
    if (UnsavedFanzineRegistry.fanzines.containsKey(component.fanzineId)) {
      _fanzineUnsub = UnsavedFanzineRegistry.watchFanzine(component.fanzineId).listen((fz) {
        if (mounted) {
          setState(() {
            _fanzine = {
              'id': fz.id,
              'title': fz.title,
              'volume': fz.volume,
              'issue': fz.issue,
              'wholeNumber': fz.wholeNumber,
              'type': fz.type.name,
              'isLive': fz.isLive,
              'processingStatus': fz.processingStatus,
              'ownerId': fz.ownerId,
              'editors': fz.editors,
              'twoPage': fz.twoPage,
              'hasCover': fz.hasCover,
              'shortCode': fz.shortCode,
              'sourceFile': fz.sourceFile,
              'draftEntities': fz.draftEntities,
              'masterCreators': fz.masterCreators,
              'masterIndicia': fz.masterIndicia,
              'indiciaPageId': fz.indiciaPageId,
              'startMonth': fz.startMonth,
              'startYear': fz.startYear,
              'isSoftPublished': fz.isSoftPublished,
              'series': fz.series,
              'publishedDate': fz.publishedDate,
            };
            _overriddenTwoPage = null;
          });
        }
      });
      return;
    }
    _fanzineUnsub = fsListenDoc('fanzines/${component.fanzineId}', (String jsonStr) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded['exists'] == true && mounted) {
          final fzData = decoded['data'];
          final shortCode = fzData['shortCode'];
          if (shortCode != null && shortCode.toString().isNotEmpty) {
            redirectFanzinePath(context, shortCode.toString());
          }
          setState(() {
            _fanzine = fzData;
            _overriddenTwoPage = null;
          });
        }
      } catch (e) {
        print("Error listening to fanzine doc: $e");
      }
    });
  }

  void _listenToPagesDoc() {
    _cancelSubscription(_pagesUnsub);
    _pagesUnsub = null;
    if (UnsavedFanzineRegistry.fanzines.containsKey(component.fanzineId)) {
      _pagesUnsub = UnsavedFanzineRegistry.watchPages(component.fanzineId).listen((pgs) {
        if (mounted) {
          setState(() {
            _pages = pgs.map((p) => {
              '__id': p.id,
              'imageId': p.imageId,
              'imageUrl': p.imageUrl,
              'gridUrl': p.gridUrl,
              'listUrl': p.listUrl,
              'pageNumber': p.pageNumber,
              'status': p.status,
              'spreadPosition': p.spreadPosition,
              'sidePreference': p.sidePreference,
              'width': p.width,
              'height': p.height,
            }).toList();
          });
        }
      });
      return;
    }
    _pagesUnsub = fsListenQuery('fanzines/${component.fanzineId}/pages', '', '', '', 'pageNumber', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final pagesList = decoded.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['__id'] = d['id'];
          return data;
        }).toList();
        if (mounted) {
          setState(() {
            _pages = pagesList;
          });
        }
      } catch (e) {
        print("Error listening to pages stream: $e");
      }
    });
  }

  @override
  void dispose() {
    _cancelSubscription(_likesUnsub);
    _cancelSubscription(_fanzineUnsub);
    _cancelSubscription(_pagesUnsub);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      if (UnsavedFanzineRegistry.fanzines.containsKey(component.fanzineId)) {
        final fz = UnsavedFanzineRegistry.fanzines[component.fanzineId]!;
        _fanzine = {
          'id': fz.id,
          'title': fz.title,
          'volume': fz.volume,
          'issue': fz.issue,
          'wholeNumber': fz.wholeNumber,
          'type': fz.type.name,
          'isLive': fz.isLive,
          'processingStatus': fz.processingStatus,
          'ownerId': fz.ownerId,
          'editors': fz.editors,
          'twoPage': fz.twoPage,
          'hasCover': fz.hasCover,
          'shortCode': fz.shortCode,
          'sourceFile': fz.sourceFile,
          'draftEntities': fz.draftEntities,
          'masterCreators': fz.masterCreators,
          'masterIndicia': fz.masterIndicia,
          'indiciaPageId': fz.indiciaPageId,
          'startMonth': fz.startMonth,
          'startYear': fz.startYear,
          'isSoftPublished': fz.isSoftPublished,
          'series': fz.series,
          'publishedDate': fz.publishedDate,
        };
        final pgs = UnsavedFanzineRegistry.pages[component.fanzineId] ?? [];
        _pages = pgs.map((p) => {
          '__id': p.id,
          'pageNumber': p.pageNumber,
          'imageId': p.imageId,
          'imageUrl': p.imageUrl,
          'gridUrl': p.gridUrl,
          'listUrl': p.listUrl,
          'status': p.status,
          'spreadPosition': p.spreadPosition,
          'sidePreference': p.sidePreference,
          'width': p.width,
          'height': p.height,
        }).toList();
        _creatorProfiles = {};
        _imageStats = {};
        _loading = false;
        return;
      }
      final fzRes = await fsGetDoc('fanzines/${component.fanzineId}');
      final fzDoc = jsonDecode(fzRes);
      if (fzDoc['exists']) {
        _fanzine = fzDoc['data'];
        final shortCode = _fanzine?['shortCode'];
        if (shortCode != null && shortCode.toString().isNotEmpty) {
          redirectFanzinePath(context, shortCode.toString());
        }
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
        for (final uid in uidsToFetch) {
          parallelFetches.add(
            fsGetDoc('profiles/$uid').then((pRes) {
              final pDoc = jsonDecode(pRes);
              if (pDoc['exists']) profiles[uid] = pDoc['data'];
            }),
          );
        }
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
        [p([text('Loading fanzine...')])],
        classes: 'flex-col items-center justify-center w-full',
        attributes: const {'style': 'min-height: 100vh;'},
      );
    }
    if (_fanzine == null) {
      return div(
        [
          p([text('Fanzine not found.')]),
          a(href: '/', [text('Go Home')])
        ],
        classes: 'flex-col items-center justify-center w-full',
        attributes: const {'style': 'min-height: 100vh;'},
      );
    }
    final String fanzineType = _fanzine!['type'] ?? 'ingested';
    final bool isCuratorZine = fanzineType == 'ingested';

    final Component listHeader = component.isEditingMode
        ? (isCuratorZine
        ? FanzineCurator(
      frefFanzineId: component.fanzineId,
      shortCode: _fanzine!['shortCode'],
      fanzineData: _fanzine,
      creatorProfiles: _creatorProfiles,
      imageStats: _imageStats,
      pageStructure: _pages,
      authState: component.authState,
      authBloc: component.authBloc,
      twoPage: _overriddenTwoPage ?? _fanzine!['twoPage'] ?? true,
      onTwoPageChanged: (val) {
        setState(() {
          _overriddenTwoPage = val;
        });
      },
    )
        : FanzineEditor(
      frefFanzineId: component.fanzineId,
      shortCode: _fanzine!['shortCode'],
      fanzineData: _fanzine,
      creatorProfiles: _creatorProfiles,
      imageStats: _imageStats,
      pageStructure: _pages,
      authState: component.authState,
      authBloc: component.authBloc,
      twoPage: _overriddenTwoPage ?? _fanzine!['twoPage'] ?? true,
      onTwoPageChanged: (val) {
        setState(() {
          _overriddenTwoPage = val;
        });
      },
    ))
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

    return div(
      [
        FanzineLayout(
          fanzineId: component.fanzineId,
          pages: _pages,
          hasCover: _fanzine!['hasCover'] ?? true,
          twoPage: _overriddenTwoPage ?? _fanzine!['twoPage'] ?? true,
          initialPageNumber: component.initialPageNumber,
          preloadedImageStats: _imageStats,
          likedImageIds: _likedImageIds,
          authState: component.authState,
          authBloc: component.authBloc,
          isEditingMode: component.isEditingMode,
          gridHeader: gridHeader,
          listHeader: listHeader,
        )
      ],
      classes: 'w-full h-full',
    );
  }
}