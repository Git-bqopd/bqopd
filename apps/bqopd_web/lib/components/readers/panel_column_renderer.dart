import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../panels/panel_container.dart';
import '../panels/text_reader_panel.dart';
import '../panels/comments_panel.dart';

/// Renders the third column for Desktop view in Jaspr.
/// Matches the Flutter PanelColumnRenderer logic.
class PanelColumnRenderer extends StatelessComponent {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final BonusRowType activePanel;
  final VoidCallback onClose;

  const PanelColumnRenderer({
    required this.fanzineId,
    required this.pages,
    required this.activePanel,
    required this.onClose,
  });

  @override
  Component build(BuildContext context) {
    String title = activePanel.name.toUpperCase();
    if (activePanel == BonusRowType.textReader) title = "Reader";
    if (activePanel == BonusRowType.comments) title = "Comments";

    return div(classes: 'flex-col h-full', [
      // Header
      div(classes: 'p-4 bg-gray-100 flex-row justify-between items-center', [
        span(classes: 'font-bold text-sm', [text(title)]),
        button(
            classes: 'cursor-pointer border-none bg-transparent',
            events: {'click': (e) => onClose()},
            [span(classes: 'material-symbols-outlined', [text('close')])]
        )
      ]),

      // Scrollable List of Panels (one per page)
      div(classes: 'flex-1 overflow-y-auto p-4', [
        for (var page in pages)
          _buildPagePanel(page)
      ])
    ]);
  }

  Component _buildPagePanel(Map<String, dynamic> pageData) {
    final imageId = pageData['imageId'] ?? '';
    if (imageId.isEmpty) return div([]);

    final pageNum = pageData['pageNumber'] ?? '?';

    return div(classes: 'mb-8', [
      p(classes: 'text-xs font-bold text-gray mb-2', [text('PAGE $pageNum')]),
      if (activePanel == BonusRowType.textReader)
        TextReaderPanel(imageId: imageId)
      else if (activePanel == BonusRowType.comments)
        CommentsPanel(imageId: imageId)
      else
        div([text('Panel type not yet implemented in web column.')])
    ]);
  }
}