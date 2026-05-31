import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../panels/panel_container.dart';
import '../panels/text_reader_panel.dart';
import '../panels/comments_panel.dart';
import '../panels/master_text_panel.dart';
import '../panels/linked_text_panel.dart';
import '../panels/entities_panel.dart';
import '../panels/raw_text_panel.dart';
import '../panels/indicia_panel.dart';
import '../panels/credits_panel.dart';
import '../panels/youtube_panel.dart';
import '../panels/analytics_panel.dart';

/// Renders the third column for Desktop view in Jaspr.
/// Matches the Flutter PanelColumnRenderer logic.
class PanelColumnRenderer extends StatelessComponent {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final BonusRowType activePanel;
  final bool isEditingMode;
  final VoidCallback onClose;

  const PanelColumnRenderer({
    required this.fanzineId,
    required this.pages,
    required this.activePanel,
    this.isEditingMode = false,
    required this.onClose,
  });

  @override
  Component build(BuildContext context) {
    String title = activePanel.name.toUpperCase();
    if (activePanel == BonusRowType.textReader) title = ""; // Omit 'Reader' text on desktop column headers too
    if (activePanel == BonusRowType.comments) title = "Comments";
    if (activePanel == BonusRowType.masterText) title = ""; // Omit 'Corrected Text Editor' on desktop column headers too
    if (activePanel == BonusRowType.linkedText) title = ""; // Omit 'Wiki-Link Editor' title on desktop column headers too
    if (activePanel == BonusRowType.entities) title = ""; // Omit 'Page Entities' text on desktop column headers too

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
      else if (activePanel == BonusRowType.masterText)
          MasterTextPanel(imageId: imageId, fanzineId: fanzineId)
        else if (activePanel == BonusRowType.linkedText)
            LinkedTextPanel(imageId: imageId, fanzineId: fanzineId)
          else if (activePanel == BonusRowType.entities)
              EntitiesPanel(imageId: imageId, fanzineId: fanzineId, isEditingMode: isEditingMode)
            else if (activePanel == BonusRowType.rawText)
                RawTextPanel(imageId: imageId)
              else if (activePanel == BonusRowType.indicia)
                  IndiciaPanel(fanzineId: fanzineId, isEditingMode: isEditingMode)
                else if (activePanel == BonusRowType.credits)
                    CreditsPanel(imageId: imageId)
                  else if (activePanel == BonusRowType.youtube)
                      YoutubePanel(imageId: imageId)
                    else if (activePanel == BonusRowType.analyticsDashboard)
                        AnalyticsPanel(imageId: imageId)
                      else
                        div([text('Panel type not yet implemented in web column.')])
    ]);
  }
}