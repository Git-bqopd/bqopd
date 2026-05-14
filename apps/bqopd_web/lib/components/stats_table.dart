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
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (component.isFanzine) {
      // Load all pages for this fanzine
      final res = await fsQuery('fanzines/${component.contentId}/pages', '', '', '', 'pageNumber');
      final List pages = jsonDecode(res);

      List<Map<String, dynamic>> loadedRows = [];
      for (var p in pages) {
        final data = p['data'];
        final imageId = data['imageId'] ?? '';
        final pageNum = data['pageNumber'] ?? '?';

        if (imageId.isNotEmpty) {
          final imgRes = await fsGetDoc('images/$imageId');
          final imgDoc = jsonDecode(imgRes);
          if (imgDoc['exists']) {
            final imgData = imgDoc['data'];
            loadedRows.add({
              'label': '$pageNum',
              'regGrid': imgData['regGridCount'] ?? 0,
              'anonGrid': imgData['anonGridCount'] ?? 0,
              'regList': imgData['regListCount'] ?? 0,
              'anonList': imgData['anonListCount'] ?? 0,
            });
          } else {
            loadedRows.add({'label': '$pageNum', 'regGrid': 0, 'anonGrid': 0, 'regList': 0, 'anonList': 0});
          }
        } else {
          loadedRows.add({'label': '$pageNum', 'regGrid': 0, 'anonGrid': 0, 'regList': 0, 'anonList': 0});
        }
      }
      setState(() {
        _rows = loadedRows;
        _loading = false;
      });
    } else {
      // Just a single image
      final imgRes = await fsGetDoc('images/${component.contentId}');
      final imgDoc = jsonDecode(imgRes);
      if (imgDoc['exists']) {
        final imgData = imgDoc['data'];
        setState(() {
          _rows = [{
            'label': '',
            'regGrid': imgData['regGridCount'] ?? 0,
            'anonGrid': imgData['anonGridCount'] ?? 0,
            'regList': imgData['regListCount'] ?? 0,
            'anonList': imgData['anonListCount'] ?? 0,
          }];
          _loading = false;
        });
      } else {
        setState(() {
          _rows = [{'label': '', 'regGrid': 0, 'anonGrid': 0, 'regList': 0, 'anonList': 0}];
          _loading = false;
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'flex-col items-center justify-center p-4', [text('Loading stats...')]);
    }

    final title = component.isFanzine ? "IMAGE ANALYTICS (GLOBAL LIFETIME)" : "VIEWER BREAKDOWN";
    final includeLabelColumn = component.isFanzine;

    return div(classes: 'flex-col items-center w-full mt-4', [
      p(classes: 'text-xs font-bold text-gray mb-4', attributes: {'style': 'letter-spacing: 1.1px;'}, [text(title)]),
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
            for (var r in _rows)
              tr([
                if (includeLabelColumn) td([text(r['label'])]),
                td([text('${r['regGrid']}')]),
                td([text('${r['anonGrid']}')]),
                td(classes: 'highlight', [text('${r['regList']}')]),
                td([text('${r['anonList']}')]),
              ])
          ])
        ])
      ])
    ]);
  }
}