import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../utils/web_firebase_interop.dart';
import '../components/fanzine_header.dart';
import '../components/fanzine_layout.dart';

class FanzineReaderPage extends StatefulComponent {
  final String fanzineId;

  const FanzineReaderPage({
    required this.fanzineId,
    super.key,
  });

  @override
  State<FanzineReaderPage> createState() => _FanzineReaderPageState();
}

class _FanzineReaderPageState extends State<FanzineReaderPage> {
  Map<String, dynamic>? _fanzine;
  List<Map<String, dynamic>> _pages = [];
  Map<String, Map<String, dynamic>> _creatorProfiles = {};
  Map<String, Map<String, dynamic>> _imageStats = {}; // Cache for stats
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 1. Load Fanzine Metadata
      final fzRes = await fsGetDoc('fanzines/${component.fanzineId}');
      final fzDoc = jsonDecode(fzRes);

      if (fzDoc['exists']) {
        _fanzine = fzDoc['data'];

        // 2. Load Pages first so we know which images to fetch stats for
        final pagesRes = await fsQuery('fanzines/${component.fanzineId}/pages', '', '', '', 'pageNumber');
        final List pagesList = jsonDecode(pagesRes);
        _pages = pagesList.map((p) {
          final data = p['data'] as Map<String, dynamic>;
          data['__id'] = p['id']; // Store internal ID
          return data;
        }).toList();

        // 3. Parallel Batch Fetching: Profiles and Image Stats
        final creators = _fanzine!['masterCreators'] as List? ?? [];
        final Map<String, Map<String, dynamic>> profiles = {};
        final Map<String, Map<String, dynamic>> stats = {};

        // Get UIDs for profiles
        final Set<String> uidsToFetch = creators
            .map((c) => c['uid'] as String?)
            .where((uid) => uid != null && uid.isNotEmpty)
            .cast<String>()
            .toSet();

        // Get Image IDs for stats
        final Set<String> imageIdsToFetch = _pages
            .map((p) => p['imageId'] as String?)
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toSet();

        // Perform fetches
        await Future.wait([
          ...uidsToFetch.map((uid) async {
            final pRes = await fsGetDoc('profiles/$uid');
            final pDoc = jsonDecode(pRes);
            if (pDoc['exists']) profiles[uid] = pDoc['data'];
          }),
          ...imageIdsToFetch.map((id) async {
            final iRes = await fsGetDoc('images/$id');
            final iDoc = jsonDecode(iRes);
            if (iDoc['exists']) stats[id] = iDoc['data'];
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
      return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
        p([text('Loading fanzine...')])
      ]);
    }

    if (_fanzine == null) {
      return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
        p([text('Fanzine not found.')]),
        a(href: '/', [text('Go Home')])
      ]);
    }

    return div(classes: 'w-full h-full', [
      FanzineLayout(
        fanzineId: component.fanzineId,
        pages: _pages,
        hasCover: _fanzine!['hasCover'] ?? true,
        headerWidget: FanzineHeader(
          fanzineId: component.fanzineId,
          shortCode: _fanzine!['shortCode'],
          fanzineData: _fanzine,
          creatorProfiles: _creatorProfiles,
          imageStats: _imageStats, // Passing the full stats package down
          pageStructure: _pages, // Passing page structure for the stats table
        ),
      )
    ]);
  }
}