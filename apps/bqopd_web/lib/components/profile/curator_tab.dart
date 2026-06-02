import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Curator Tab containing review lists, queue allocations, and baseline parameters.
class CuratorTab extends StatefulComponent {
  final List<Map<String, dynamic>> userWorks;
  final List<Map<String, dynamic>> aiTrainingData;
  final int initialSubTab;
  final void Function(int) onSubTabChanged;

  const CuratorTab({
    required this.userWorks,
    required this.aiTrainingData,
    required this.initialSubTab,
    required this.onSubTabChanged,
    super.key,
  });

  @override
  State<CuratorTab> createState() => _CuratorTabState();
}

class _CuratorTabState extends State<CuratorTab> {
  int _activeSubTab = 0;

  @override
  void initState() {
    super.initState();
    _activeSubTab = component.initialSubTab;
  }

  @override
  void didUpdateComponent(CuratorTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialSubTab != component.initialSubTab) {
      _activeSubTab = component.initialSubTab;
    }
  }

  Component _buildWorkGridTile(Map<String, dynamic> w) {
    final String fanzineId = w['id'] ?? '';
    final String title = w['title'] ?? 'Untitled Fanzine';
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
        p([text('No items in queue.')], classes: 'text-sm text-gray italic mt-4')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }
    return div([
      for (var w in works)
        _buildWorkGridTile(w)
    ], attributes: const {
      'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
    });
  }

  Component _buildCuratorEntitiesList() {
    final Map<String, int> entityCounts = {};
    for (var fz in component.userWorks) {
      final List entities = fz['draftEntities'] ?? [];
      for (var ent in entities) {
        entityCounts[ent.toString()] = (entityCounts[ent.toString()] ?? 0) + 1;
      }
    }
    if (entityCounts.isEmpty) {
      return div([
        p([text("No entities detected in draft curator pipeline.")], classes: 'text-sm text-gray italic')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }
    final sortedNames = entityCounts.keys.toList()..sort((a, b) => entityCounts[b]!.compareTo(entityCounts[a]!));
    return div([
      h2([text("DETECTED DRAFT ENTITIES")], classes: 'font-bold text-sm text-gray mb-4'),
      for (var name in sortedNames)
        div([
          span([text(name)], attributes: const {'style': 'font-weight: bold;'}),
          span([text('${entityCounts[name]} occurrences')], attributes: const {'style': 'color: #888; font-size: 11px;'})
        ], attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #eee; font-size: 13px;'})
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-3');
  }

  Component _buildAITrainingDataPortal() {
    final trainingItems = component.aiTrainingData;
    if (trainingItems.isEmpty) {
      return div([
        p([text("No training data yet.")], classes: 'text-sm text-gray italic')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }
    return div([
      h2([text("AI REINFORCEMENT BASELINES")], classes: 'font-bold text-sm text-gray mb-2'),
      for (var item in trainingItems)
        div([
          if (item['fileUrl'] != null)
            img(src: item['fileUrl'], attributes: const {'style': 'width: 48px; height: 48px; object-fit: cover; border-radius: 4px; border: 1px solid #ccc;'}),
          span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
          div([
            span([text(item['title'] ?? 'Archival Page')], attributes: const {'style': 'font-weight: bold;'}),
            span([
              text("Correction Score: ${item['correctionScore'] ?? 0} | Link Score: ${item['linkingScore'] ?? 0}")
            ], attributes: const {'style': 'font-size: 11px; color: #666;'})
          ], attributes: const {'style': 'display: flex; align-items: center; padding: 12px; border: 1px solid #eee; border-radius: 8px; font-size: 13px;'})
        ], attributes: const {'style': 'display: flex; align-items: center; padding: 12px; border: 1px solid #eee; border-radius: 8px; font-size: 13px;'})
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  @override
  Component build(BuildContext context) {
    return div([
      div([
        span([text("curator inbox")], classes: _activeSubTab == 0 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
          'click': (e) {
            setState(() => _activeSubTab = 0);
            component.onSubTabChanged(0);
          }
        }),
        span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
        span([text("publisher queue")], classes: _activeSubTab == 1 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
          'click': (e) {
            setState(() => _activeSubTab = 1);
            component.onSubTabChanged(1);
          }
        }),
        span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
        span([text("wiki entities")], classes: _activeSubTab == 2 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
          'click': (e) {
            setState(() => _activeSubTab = 2);
            component.onSubTabChanged(2);
          }
        }),
        span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
        span([text("ai baseline")], classes: _activeSubTab == 3 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
          'click': (e) {
            setState(() => _activeSubTab = 3);
            component.onSubTabChanged(3);
          }
        }),
      ], classes: 'bg-white rounded-md p-4 shadow-sm', attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 8px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}),

      if (_activeSubTab == 0)
        _buildWorksGridSchema(component.userWorks.where((w) => w['sourceFile'] != null && w['isLive'] != true).toList())
      else if (_activeSubTab == 1)
        _buildWorksGridSchema(component.userWorks.where((w) => w['sourceFile'] == null || w['isLive'] == true).toList())
      else if (_activeSubTab == 2)
          _buildCuratorEntitiesList()
        else
          _buildAITrainingDataPortal()
    ]);
  }
}