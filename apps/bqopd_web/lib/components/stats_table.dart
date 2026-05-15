import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../utils/web_firebase_interop.dart';

class StatsTable extends StatefulComponent {
  final String contentId;
  final bool isFanzine;

  const StatsTable({
    required this.contentId,
    this.isFanzine = false,
  });

  @override
  State<StatsTable> createState() => _StatsTableState();
}

class _StatsTableState extends State<StatsTable> {
  List<Map<String, dynamic>> _pages = [];
  bool _loadingPages = true;

  @override
  void initState() {
    super.initState();
    _fetchPageList();
  }

  /// Fetches only the list of page identifiers.
  /// The specific stats for each image will be loaded reactively in the rows.
  Future<void> _fetchPageList() async {
    if (!component.isFanzine) {
      setState(() => _loadingPages = false);
      return;
    }

    try {
      final res = await fsQuery('fanzines/${component.contentId}/pages', '', '', '', 'pageNumber');
      final List pages = jsonDecode(res);
      setState(() {
        _pages = pages.map((p) => p as Map<String, dynamic>).toList();
        _loadingPages = false;
      });
    } catch (e) {
      print("Error loading page list: $e");
      setState(() => _loadingPages = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loadingPages) {
      return div(classes: 'flex-col items-center justify-center p-4', [
        p([text('Loading page structure...')])
      ]);
    }

    final includeLabelColumn = component.isFanzine;

    return div(classes: 'flex-col items-center w-full mt-4', [
      div(classes: 'stats-table-wrapper', [
        table(classes: 'stats-table', [
          thead([
            tr([
              if (includeLabelColumn) th(attributes: {'rowspan': '2'}, [text('Page')]),
              th(attributes: {'colspan': '2'}, [
                span(classes: 'material-symbols-outlined', attributes: {'style': 'font-size: 14px; vertical-align: middle; margin-right: 4px;'}, [text('grid_view')]),
                text('Grid (Glance)')
              ]),
              th(attributes: {'colspan': '2'}, [
                span(classes: 'material-symbols-outlined', attributes: {'style': 'font-size: 14px; vertical-align: middle; margin-right: 4px;'}, [text('view_list')]),
                text('List (Read)')
              ]),
            ]),
            tr([
              th([text('User')]),
              th([text('Anon')]),
              th([text('User')]),
              th([text('Anon')]),
            ])
          ]),
          tbody([
            if (!component.isFanzine)
              StatRow(imageId: component.contentId, label: null)
            else
              for (var p in _pages)
                StatRow(
                    imageId: p['data']['imageId'] ?? '',
                    label: '${p['data']['pageNumber'] ?? '?'}'
                )
          ])
        ])
      ])
    ]);
  }
}

/// A reactive table row that listens to a specific image's stats.
class StatRow extends StatefulComponent {
  final String imageId;
  final String? label;

  const StatRow({required this.imageId, this.label});

  @override
  State<StatRow> createState() => _StatRowState();
}

class _StatRowState extends State<StatRow> {
  Map<String, dynamic>? _data;
  dynamic _unsub;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    if (component.imageId.isEmpty) return;

    // Use the interop listener for real-time updates and "pop-in" effect
    _unsub = fsListenDoc('images/${component.imageId}', (jsonStr) {
      final doc = jsonDecode(jsonStr);
      if (doc['exists']) {
        setState(() {
          _data = doc['data'];
        });
      }
    });
  }

  @override
  void dispose() {
    if (_unsub != null) {
      _unsub.callAsFunction();
    }
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final regGrid = _data?['regGridCount'] ?? 0;
    final anonGrid = _data?['anonGridCount'] ?? 0;
    final regList = _data?['regListCount'] ?? 0;
    final anonList = _data?['anonListCount'] ?? 0;

    return tr([
      if (component.label != null) td([text(component.label!)]),
      td([text('$regGrid')]),
      td([text('$anonGrid')]),
      td(classes: 'highlight', [text('$regList')]),
      td([text('$anonList')]),
    ]);
  }
}