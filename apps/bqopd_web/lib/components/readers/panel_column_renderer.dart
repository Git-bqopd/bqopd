import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../panels/panel_container.dart';
import '../panels/text_reader_panel.dart';
import '../panels/comments_panel.dart';
import '../panels/edit_text_panel.dart';
import '../panels/entities_panel.dart';
import '../panels/raw_text_panel.dart';
import '../panels/indicia_panel.dart';
import '../panels/credits_panel.dart';
import '../panels/youtube_panel.dart';
import '../panels/analytics_panel.dart';
import '../panels/publisher_text_panel.dart';

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
    if (activePanel == BonusRowType.textReader) title = ""; // Omit 'Reader' text
    if (activePanel == BonusRowType.comments) title = "Comments";
    if (activePanel == BonusRowType.editText) title = ""; // FIXED: Omit 'Edit Text' title using the updated enum name
    if (activePanel == BonusRowType.entities) title = ""; // Omit 'Page Entities' text
    if (activePanel == BonusRowType.newPage) title = "New Page Layout Editor";

    final bool isSingleton = activePanel == BonusRowType.settings || activePanel == BonusRowType.youtube;

    return div(
        [
          // Header
          div(classes: 'p-4 bg-gray-100 flex-row justify-between items-center', attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #e0e0e0; flex-shrink: 0;'}, [
            span([text(title)], attributes: const {'style': 'font-weight: bold; font-size: 13px; letter-spacing: 0.5px; text-transform: uppercase;'}),
            button(
                classes: 'cursor-pointer border-none bg-transparent',
                events: {'click': (e) => onClose()},
                [span(classes: 'material-symbols-outlined', [text('close')])]
            )
          ]),
          // Scrollable List of Panels
          div(classes: 'flex-1 overflow-y-auto p-4', attributes: const {'style': 'overflow-y: auto; flex: 1; padding: 16px;'}, [
            if (isSingleton)
              _buildPagePanel(pages.isNotEmpty ? pages.first : {})
            else
              for (var page in pages)
                _buildPagePanel(page)
          ])
        ],
        attributes: const {'style': 'width: 100%; height: 100%; display: flex; flex-direction: column; overflow: hidden;'}
    );
  }

  Component _buildPagePanel(Map<String, dynamic> pageData) {
    final imageId = pageData['imageId'] ?? '';
    if (imageId.isEmpty) return div([]);
    final pageNum = pageData['pageNumber'] ?? '?';
    return div(classes: 'mb-8', [
      p(classes: 'text-xs font-bold text-gray mb-2', [text('PAGE $pageNum')]),
      if (activePanel == BonusRowType.textReader)
        TextReaderPanel(imageId: imageId, fanzineId: fanzineId)
      else if (activePanel == BonusRowType.comments)
        CommentsPanel(imageId: imageId)
      else if (activePanel == BonusRowType.editText || activePanel == BonusRowType.linkedText) // FIXED: Uses matching editText enum name
          EditTextPanel(imageId: imageId, fanzineId: fanzineId)
        else if (activePanel == BonusRowType.entities)
            EntitiesPanel(imageId: imageId, fanzineId: fanzineId, isEditingMode: false) // ALWAYS reader mode from main toolbar column
          else if (activePanel == BonusRowType.rawText)
              RawTextPanel(imageId: imageId)
            else if (activePanel == BonusRowType.indicia)
                IndiciaPanel(fanzineId: fanzineId, isEditingMode: false) // ALWAYS reader mode from main toolbar column
              else if (activePanel == BonusRowType.credits)
                  CreditsPanel(imageId: imageId)
                else if (activePanel == BonusRowType.youtube)
                    YoutubePanel(imageId: imageId)
                  else if (activePanel == BonusRowType.analyticsDashboard)
                      AnalyticsPanel(imageId: imageId)
                    else if (activePanel == BonusRowType.newPage)
                        PublisherTextPanel(imageId: imageId, fanzineId: fanzineId)
                      else
                        div([text('Panel type not yet implemented in web column.')])
    ]);
  }
}