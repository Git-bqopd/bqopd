import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../stats_table.dart';
import '../panels/comments_panel.dart';

/// Module displaying mentions list grids and user comments.
class IndexTab extends StatefulComponent {
  final List<Map<String, dynamic>> mentions;
  final List<Map<String, dynamic>> comments;
  final int initialSubTab;
  final void Function(int) onSubTabChanged;

  const IndexTab({
    required this.mentions,
    required this.comments,
    required this.initialSubTab,
    required this.onSubTabChanged,
    super.key,
  });

  @override
  State<IndexTab> createState() => _IndexTabState();
}

class _IndexTabState extends State<IndexTab> {
  int _activeSubTab = 0;

  @override
  void initState() {
    super.initState();
    _activeSubTab = component.initialSubTab;
  }

  @override
  void didUpdateComponent(IndexTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialSubTab != component.initialSubTab) {
      _activeSubTab = component.initialSubTab;
    }
  }

  Component _buildWorkGridTile(Map<String, dynamic> w) {
    final String fanzineId = w['id'] ?? '';
    final String title = w['title'] ?? 'Untitled Fanzine';
    final String volume = w['volume'] ?? '';
    final String issue = w['issue'] ?? '';
    final String wholeNumber = w['wholeNumber'] ?? '';
    String displaySuffix = '';
    if (volume.isNotEmpty) displaySuffix += " Vol. $volume";
    if (issue.isNotEmpty) displaySuffix += " No. $issue";
    if (wholeNumber.isNotEmpty) displaySuffix += " ($wholeNumber)";
    final String coverUrl = w['gridCoverImage'] ?? (w['sourceFile'] != null
        ? 'https://placehold.co/450x720/png?text=Archival+Ingest'
        : 'https://placehold.co/450x720/png?text=Folio');

    final String codeKey = w['shortCode'] ?? fanzineId;
    return a(
        [
          div([
            div([text(w['type'] ?? 'ingested')], attributes: const {
              'style': 'position: absolute; top: 8px; left: 8px; background-color: rgba(0,0,0,0.7); color: white; padding: 2px 8px; border-radius: 4px; font-size: 8px; font-weight: bold; text-transform: uppercase;'
            })
          ], attributes: {
            'style': 'aspect-ratio: 5/8; background-color: #f3f4f6; background-image: url("$coverUrl"); background-size: cover; background-position: center; position: relative;'
          }),
          div([
            span([text(title)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'}),
            if (displaySuffix.isNotEmpty)
              span([text(displaySuffix)], attributes: const {'style': 'font-size: 11px; color: #666;'})
          ], attributes: const {'style': 'padding: 12px; display: flex; flex-direction: column; gap: 4px;'})
        ],
        href: '/$codeKey',
        classes: 'bg-white rounded-lg shadow-sm overflow-hidden transition-all',
        attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #ddd; cursor: pointer;'}
    );
  }

  Component _buildWorksGridSchema(List<Map<String, dynamic>> works) {
    if (works.isEmpty) {
      return div([
        span([text('library_books')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
        p([text('No mentions available yet.')], classes: 'text-sm text-gray italic mt-4')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }
    return div([
      for (var w in works)
        _buildWorkGridTile(w)
    ], attributes: const {
      'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
    });
  }

  Component _buildCommentsListSubView() {
    if (component.comments.isEmpty) {
      return div([
        span([text('chat_bubble')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
        p([text('No comments posted by this profile.')], classes: 'text-sm text-gray italic mt-4')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }
    return div([
      h2([text("COMMENTS POSTED")], classes: 'font-bold text-sm text-gray mb-4'),
      for (var c in component.comments)
        div([
          div([
            span([text(c['createdAt'] is DateTime ? (c['createdAt'] as DateTime).toIso8601String().split('T').first : '')]),
            if (c['context'] != null && c['context']['fanzineTitle'] != null)
              span([text("via ${c['context']['fanzineTitle']}")], attributes: const {'style': 'font-style: italic;'})
          ], attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between; font-size: 11px; color: #888; margin-bottom: 8px;'}),
          p([text(c['text'] ?? '')], attributes: const {'style': 'border-bottom: 1px solid #f0f0f0; padding-bottom: 16px; margin-bottom: 16px;'})
        ], attributes: const {'style': 'border-bottom: 1px solid #f0f0f0; padding-bottom: 16px; margin-bottom: 16px;'})
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  @override
  Component build(BuildContext context) {
    return div([
      // Subtab header selector
      div([
        span([text("mentions (${component.mentions.length})")], classes: _activeSubTab == 0 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
          'click': (e) {
            setState(() => _activeSubTab = 0);
            component.onSubTabChanged(0);
          }
        }),
        span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
        span([text("comments (${component.comments.length})")], classes: _activeSubTab == 1 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
          'click': (e) {
            setState(() => _activeSubTab = 1);
            component.onSubTabChanged(1);
          }
        }),
      ], classes: 'bg-white rounded-md p-4 shadow-sm', attributes: const {'style': 'display: flex; justify-content: center; align-items: center; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}),

      if (_activeSubTab == 0)
        _buildWorksGridSchema(component.mentions)
      else
        _buildCommentsListSubView()
    ]);
  }
}