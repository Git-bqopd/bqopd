import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'dart:convert';
import '../utils/web_firebase_interop.dart';
import 'stats_table.dart';

class FanzineHeader extends StatefulComponent {
  final String? fanzineId;
  final String? shortCode;
  final Map<String, dynamic>? fanzineData;
  final bool isStickerOnly;

  const FanzineHeader({
    this.fanzineId,
    this.shortCode,
    this.fanzineData,
    this.isStickerOnly = false,
  });

  @override
  State<FanzineHeader> createState() => _FanzineHeaderState();
}

class _FanzineHeaderState extends State<FanzineHeader> {
  int _activeTab = 0; // 0: indicia, 1: creators, 2: stats
  String _displayUrl = 'bqopd.com/...';

  @override
  void initState() {
    super.initState();
    _resolveDisplayUrl();
  }

  Future<void> _resolveDisplayUrl() async {
    final uid = getCurrentUserId();
    if (uid == null) {
      setState(() => _displayUrl = 'login / register');
    } else {
      final res = await fsGetDoc('profiles/$uid');
      final data = jsonDecode(res);
      if (data['exists']) {
        setState(() => _displayUrl = 'bqopd.com/${data['data']['username']}');
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (component.isStickerOnly) {
      return div(classes: 'flex-col items-center justify-center w-full h-full', [
        div(classes: 'bg-white p-4', attributes: {'style': 'border-radius: 12px; box-shadow: 0 1px 2px rgba(0,0,0,0.05);'}, [
          img(src: 'assets/logo200.gif', attributes: {'width': '100'})
        ])
      ]);
    }

    final indiciaText = component.fanzineData?['masterIndicia'] ?? "© 2026 BQOPD Collective.";
    final creators = component.fanzineData?['masterCreators'] as List? ?? [];

    return div(classes: 'flex-col items-center w-full h-full p-2', [
      button(
          classes: 'nav-pill',
          events: {'click': (e) {
            final uid = getCurrentUserId();
            if (uid == null) Router.of(context).push('/login');
            else Router.of(context).push('/profile');
          }},
          [text(_displayUrl)]
      ),
      div(classes: 'white-sticker-compact w-full mt-2', [
        div(classes: 'flex-row justify-center items-center py-2 bg-gray-100', [
          _buildTab('indicia', 0),
          span(classes: 'px-4 text-gray text-xs', [text('|')]),
          _buildTab('creators', 1),
          span(classes: 'px-4 text-gray text-xs', [text('|')]),
          _buildTab('stats', 2),
        ]),
        div(classes: 'flex-col flex-1 p-4 overflow-y-auto', [
          if (_activeTab == 0) p(classes: 'text-xs text-justify', attributes: {'style': 'font-family: Georgia; line-height: 1.5;'}, [text(indiciaText)]),
          if (_activeTab == 1) _buildCreatorsTab(creators),
          if (_activeTab == 2 && component.fanzineId != null) StatsTable(contentId: component.fanzineId!, isFanzine: true)
        ])
      ])
    ]);
  }

  Component _buildTab(String label, int index) {
    final isActive = _activeTab == index;
    return span(
        classes: 'text-xs cursor-pointer ${isActive ? 'font-bold' : 'text-gray'}',
        events: {'click': (e) => setState(() => _activeTab = index)},
        [text(label)]
    );
  }

  Component _buildCreatorsTab(List creators) {
    if (creators.isEmpty) return p(classes: 'text-xs text-center text-gray', [text('No creators listed.')]);
    return div(classes: 'flex-col gap-2', [
      for (var c in creators)
        div(classes: 'flex-row items-center gap-2', [
          span(classes: 'text-xs text-gray font-bold', attributes: {'style': 'width: 45px; text-align: right; font-size: 8px;'}, [text('${c['role']}'.toUpperCase())]),
          span(classes: 'text-gray text-xs', [text('|')]),
          span(classes: 'text-xs font-bold', attributes: {'style': 'font-size: 10px;'}, [text('${c['name']}'.toUpperCase())])
        ])
    ]);
  }
}