import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../utils/web_firebase_interop.dart';
import '../components/fanzine_header.dart';
import '../components/fanzine_layout.dart';

class FanzineReaderPage extends StatefulComponent {
  final String fanzineId;
  final int? initialPageNumber;
  final Map<String, dynamic>? preloadedFanzine;
  final List<Map<String, dynamic>>? preloadedPages;
  final Map<String, Map<String, dynamic>>? preloadedCreatorProfiles;
  final Map<String, Map<String, dynamic>>? preloadedImageStats;

  const FanzineReaderPage({
    required this.fanzineId,
    this.initialPageNumber,
    this.preloadedFanzine,
    this.preloadedPages,
    this.preloadedCreatorProfiles,
    this.preloadedImageStats,
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

  @override
  void initState() {
    super.initState();
    // VITAL: Instant mount using pre-fetched payloads. No client-side layout thrashing.
    if (component.preloadedFanzine != null && component.preloadedPages != null) {
      _fanzine = component.preloadedFanzine;
      _pages = component.preloadedPages!;
      _creatorProfiles = component.preloadedCreatorProfiles ?? {};
      _imageStats = component.preloadedImageStats ?? {};
      _loading = false;
    } else if (kIsWeb) {
      _loadData();
    }
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

        // HIGH PERFORMANCE: Skip preloading image collection metadata.
        // Eliminates massive parallel query blockages during startup.
        await Future.wait([
          ...uidsToFetch.map((uid) async {
            final pRes = await fsGetDoc('profiles/$uid');
            final pDoc = jsonDecode(pRes);
            if (pDoc['exists']) profiles[uid] = pDoc['data'];
          }),
        ]);

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

    return div(classes: 'w-full h-full', [
      FanzineLayout(
        fanzineId: component.fanzineId,
        pages: _pages,
        hasCover: _fanzine!['hasCover'] ?? true,
        initialPageNumber: component.initialPageNumber,
        preloadedImageStats: _imageStats,
        headerWidget: FanzineHeader(
          fanzineId: component.fanzineId,
          shortCode: _fanzine!['shortCode'],
          fanzineData: _fanzine,
          creatorProfiles: _creatorProfiles,
          imageStats: _imageStats,
          pageStructure: _pages,
        ),
      )
    ]);
  }
}