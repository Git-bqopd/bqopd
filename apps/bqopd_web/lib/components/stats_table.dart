import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// A high-performance, stateless table for displaying view analytics.
/// This component is designed to render instantly using a pre-loaded
/// data package provided by the parent FanzineReaderPage.
class StatsTable extends StatelessComponent {
  final String contentId;
  final bool isFanzine;
  final List<Map<String, dynamic>> preloadedPages;
  final Map<String, Map<String, dynamic>> preloadedStats;

  const StatsTable({
    required this.contentId,
    this.isFanzine = false,
    this.preloadedPages = const [],
    this.preloadedStats = const {},
    super.key,
  });

  @override
  Component build(BuildContext context) {
    final includeLabelColumn = isFanzine;

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
            if (!isFanzine)
            // Single image mode
              _renderRow(contentId, null)
            else
            // Multi-page fanzine mode: render every row immediately from cache
              for (var p in preloadedPages)
                _renderRow(
                    p['imageId'] ?? '',
                    '${p['pageNumber'] ?? '?'}'
                )
          ])
        ])
      ])
    ]);
  }

  /// Renders a single row in the stats table.
  /// No state, no streams, no delay.
  Component _renderRow(String imageId, String? label) {
    final stats = preloadedStats[imageId] ?? {};

    final regGrid = stats['regGridCount'] ?? 0;
    final anonGrid = stats['anonGridCount'] ?? 0;
    final regList = stats['regListCount'] ?? 0;
    final anonList = stats['anonListCount'] ?? 0;

    return tr([
      if (label != null) td([text(label)]),
      td([text('$regGrid')]),
      td([text('$anonGrid')]),
      td(classes: 'highlight', [text('$regList')]),
      td([text('$anonList')]),
    ]);
  }
}