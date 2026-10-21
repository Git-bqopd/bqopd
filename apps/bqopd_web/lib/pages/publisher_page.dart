import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/firebase_mocks.dart';
import '../utils/unsaved_fanzine_registry.dart';
import '../components/fanzine_header.dart';
import '../components/fanzine_editor.dart';
import '../components/fanzine_layout.dart';

/// Top-level coordinator page for the dedicated `/publisher` production desk.
/// Operates as an application-level workspace that initializes with an empty folio canvas,
/// keeps Columns 1, 2, and 3 open by default, and supports loading or switching between
/// different fanzines in a single continuous session.
class PublisherPage extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc? authBloc;
  final IUserRepository? userRepository;
  final IEngagementRepository? engagementRepository;

  const PublisherPage({
    this.authState,
    this.authBloc,
    this.userRepository,
    this.engagementRepository,
    super.key,
  });

  @override
  State<PublisherPage> createState() => _PublisherPageState();
}

class _PublisherPageState extends State<PublisherPage> {
  String _activeFanzineId = '';
  Map<String, dynamic>? _fanzineData;
  List<Map<String, dynamic>> _pages = [];
  Map<String, Map<String, dynamic>> _creatorProfiles = {};
  Map<String, Map<String, dynamic>> _imageStats = {};
  bool _loading = false;
  Set<String> _likedImageIds = {};
  bool? _overriddenTwoPage;

  dynamic _likesUnsub;
  dynamic _fanzineUnsub;
  dynamic _pagesUnsub;

  @override
  void initState() {
    super.initState();
    _initBlankFolioSession();
    _setupLikesPipeline();
  }

  @override
  void dispose() {
    _cancelSubscription(_likesUnsub);
    _cancelSubscription(_fanzineUnsub);
    _cancelSubscription(_pagesUnsub);
    super.dispose();
  }

  void _cancelSubscription(dynamic unsub) {
    if (unsub == null) return;
    if (unsub is StreamSubscription) {
      unsub.cancel();
    } else if (unsub is FirebaseSubscription) {
      unsub.callAsFunction();
    }
  }

  void _setupLikesPipeline() {
    if (kIsWeb) {
      _listenToUserLikes();
      onAuthStateChangedListener((uid, email) {
        _listenToUserLikes();
      });
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
    _likesUnsub = fsListenQuery(
      'Users/$uid/activity/likes/images',
      '',
      '',
      '',
      '',
      false,
          (jsonStr) {
        try {
          final List decoded = jsonDecode(jsonStr);
          final Set<String> likedIds = decoded
              .map((d) {
            final data = d['data'] as Map<String, dynamic>? ?? {};
            return data['imageId']?.toString() ?? d['id']?.toString() ?? '';
          })
              .where((id) => id.isNotEmpty)
              .toSet();
          if (mounted) {
            setState(() {
              _likedImageIds = likedIds;
            });
          }
        } catch (e) {
          print('[PublisherPage] Error parsing likes: $e');
        }
      },
    );
  }

  /// Initializes an in-memory session with an empty draft folio.
  /// Matches the visual layout of clicking [make] -> [folio] in profile maker.
  void _initBlankFolioSession() {
    final uid = component.authState?.user?.uid ?? getCurrentUserId() ?? 'system';
    final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
    final shortCode = ShortcodeGenerator.generateStandardCode();

    final newFanzine = Fanzine(
      id: fanzineId,
      title: 'new folio name',
      ownerId: uid,
      curators: [uid],
      collections: [uid],
      type: FanzineType.folio,
      isLive: false,
      processingStatus: 'complete',
      shortCode: shortCode,
      twoPage: true,
      hasCover: true,
    );

    UnsavedFanzineRegistry.add(newFanzine, []);

    _activeFanzineId = fanzineId;
    _fanzineData = {
      'id': newFanzine.id,
      'title': newFanzine.title,
      'type': newFanzine.type.name,
      'isLive': newFanzine.isLive,
      'processingStatus': newFanzine.processingStatus,
      'ownerId': newFanzine.ownerId,
      'curators': newFanzine.curators,
      'collections': newFanzine.collections,
      'twoPage': newFanzine.twoPage,
      'hasCover': newFanzine.hasCover,
      'shortCode': newFanzine.shortCode,
    };
    _pages = [];
    _loading = false;

    if (kIsWeb) {
      _listenToActiveFanzine();
    }
  }

  /// Swaps or loads a different fanzine into the active publisher session
  /// without closing the browser window or tearing down the route.
  Future<void> loadFanzine(String identifier) async {
    final clean = identifier.trim();
    if (clean.isEmpty) return;

    setState(() => _loading = true);

    try {
      // 1. Check in-memory UnsavedFanzineRegistry first
      if (UnsavedFanzineRegistry.hasCode(clean)) {
        final fz = UnsavedFanzineRegistry.getByCode(clean)!;
        _activeFanzineId = fz.id;
        _listenToActiveFanzine();
        setState(() => _loading = false);
        return;
      }
      if (UnsavedFanzineRegistry.fanzines.containsKey(clean)) {
        _activeFanzineId = clean;
        _listenToActiveFanzine();
        setState(() => _loading = false);
        return;
      }

      // 2. Resolve via shortcode lookup or direct Firestore document ID
      String fzId = clean;
      final scRes = await fsGetDoc('shortcodes/${clean.toUpperCase()}');
      final scDoc = jsonDecode(scRes);
      if (scDoc['exists'] == true && scDoc['data']?['type'] == 'fanzine') {
        fzId = scDoc['data']['contentId'] ?? clean;
      } else {
        final queryRes = await fsQuery('fanzines', 'shortCode', '==', jsonEncode(clean), '');
        final List qList = jsonDecode(queryRes);
        if (qList.isNotEmpty) {
          fzId = qList.first['id'] ?? clean;
        }
      }

      _activeFanzineId = fzId;
      final fzRes = await fsGetDoc('fanzines/$fzId');
      final fzDoc = jsonDecode(fzRes);
      if (fzDoc['exists'] == true) {
        _fanzineData = restoreTimestamps(fzDoc['data']);
        final pagesRes = await fsQuery('fanzines/$fzId/pages', '', '', '', 'pageNumber');
        final List pList = jsonDecode(pagesRes);
        _pages = pList.map((d) {
          final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
          data['__id'] = d['id'];
          if (data['textHtml'] == null && data['text_html'] != null) {
            data['textHtml'] = data['text_html'];
          }
          return data;
        }).toList();
        _listenToActiveFanzine();
      }
    } catch (e) {
      print('[PublisherPage] Error loading fanzine: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _listenToActiveFanzine() {
    _cancelSubscription(_fanzineUnsub);
    _cancelSubscription(_pagesUnsub);
    _fanzineUnsub = null;
    _pagesUnsub = null;

    if (UnsavedFanzineRegistry.fanzines.containsKey(_activeFanzineId)) {
      _fanzineUnsub = UnsavedFanzineRegistry.watchFanzine(_activeFanzineId).listen((fz) {
        if (mounted) {
          setState(() {
            _fanzineData = {
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

      _pagesUnsub = UnsavedFanzineRegistry.watchPages(_activeFanzineId).listen((pgs) {
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
              'templateId': p.templateId,
              'spreadPosition': p.spreadPosition,
              'sidePreference': p.sidePreference,
              'width': p.width,
              'height': p.height,
              'is5x8': p.is5x8 ?? true,
              'text': p.text,
              'textHtml': p.textHtml,
              'text_html': p.textHtml,
            }).toList();
          });
        }
      });
      return;
    }

    _fanzineUnsub = fsListenDoc('fanzines/$_activeFanzineId', (String jsonStr) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded['exists'] == true && mounted) {
          setState(() {
            _fanzineData = decoded['data'];
            _overriddenTwoPage = null;
          });
        }
      } catch (e) {
        print('[PublisherPage] Error listening to fanzine doc: $e');
      }
    });

    _pagesUnsub = fsListenQuery(
      'fanzines/$_activeFanzineId/pages',
      '',
      '',
      '',
      'pageNumber',
      false,
          (String jsonStr) {
        try {
          final List decoded = jsonDecode(jsonStr);
          final pagesList = decoded.map((d) {
            final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
            data['__id'] = d['id'];
            if (data['textHtml'] == null && data['text_html'] != null) {
              data['textHtml'] = data['text_html'];
            }
            return data;
          }).toList();
          if (mounted) {
            setState(() {
              _pages = pagesList;
            });
          }
        } catch (e) {
          print('[PublisherPage] Error listening to pages stream: $e');
        }
      },
    );
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
        classes: 'flex-col items-center justify-center w-full',
        attributes: const {'style': 'min-height: 100vh;'},
        [p([Component.text('Loading publisher session...')])],
      );
    }

    final listHeader = FanzineEditor(
      frefFanzineId: _activeFanzineId,
      shortCode: _fanzineData?['shortCode'],
      fanzineData: _fanzineData,
      creatorProfiles: _creatorProfiles,
      imageStats: _imageStats,
      pageStructure: _pages,
      authState: component.authState,
      authBloc: component.authBloc,
      twoPage: _overriddenTwoPage ?? _fanzineData?['twoPage'] ?? true,
      onTwoPageChanged: (val) {
        setState(() {
          _overriddenTwoPage = val;
        });
      },
    );

    final gridHeader = FanzineHeader(
      fanzineId: _activeFanzineId,
      shortCode: _fanzineData?['shortCode'],
      fanzineData: _fanzineData,
      creatorProfiles: _creatorProfiles,
      imageStats: _imageStats,
      pageStructure: _pages,
      isStickerOnly: true,
      authState: component.authState,
      authBloc: component.authBloc,
    );

    return div(
      classes: 'w-full h-full',
      [
        FanzineLayout(
          fanzineId: _activeFanzineId,
          shortCode: _fanzineData?['shortCode'],
          fanzineType: _fanzineData?['type'] ?? 'folio',
          pages: _pages,
          hasCover: _fanzineData?['hasCover'] ?? true,
          twoPage: _overriddenTwoPage ?? _fanzineData?['twoPage'] ?? true,
          preloadedImageStats: _imageStats,
          likedImageIds: _likedImageIds,
          authState: component.authState,
          authBloc: component.authBloc,
          isEditingMode: true,
          activeScope: ToolScope.editor,
          initialPanel: BonusRowType.publisher,
          gridHeader: gridHeader,
          listHeader: listHeader,
        )
      ],
    );
  }
}