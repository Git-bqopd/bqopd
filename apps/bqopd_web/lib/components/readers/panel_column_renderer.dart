import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../panels/panel_column_templates.dart';
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
import '../panels/terminal_panel.dart';

/// Renders the third column for Desktop view in Jaspr.
/// Delegates structure to either SingleWindowColumnLayout or MultiPageColumnLayout.
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
    if (activePanel == BonusRowType.textReader) title = "";
    if (activePanel == BonusRowType.comments) title = "Comments";
    if (activePanel == BonusRowType.editText) title = "";
    if (activePanel == BonusRowType.entities) title = "";
    if (activePanel == BonusRowType.newPage) title = "New Page Layout Editor";
    if (activePanel == BonusRowType.terminal) title = "Combat Terminal";

    final bool isSingleton = activePanel == BonusRowType.settings ||
        activePanel == BonusRowType.youtube ||
        activePanel == BonusRowType.terminal ||
        activePanel == BonusRowType.analyticsDashboard;

    if (isSingleton) {
      final firstPageData = pages.isNotEmpty ? pages.first : <String, dynamic>{};
      final imageId = firstPageData['imageId'] ?? '';

      return SingleWindowColumnLayout(
        title: title,
        onClose: onClose,
        child: _buildSingletonWidget(imageId),
      );
    }

    return MultiPageColumnLayout(
      title: title,
      pages: pages,
      onClose: onClose,
      pageBuilder: (pageData) => _buildPagePanel(pageData),
    );
  }

  Component _buildSingletonWidget(String imageId) {
    switch (activePanel) {
      case BonusRowType.youtube:
        return YoutubePanel(imageId: imageId);
      case BonusRowType.analyticsDashboard:
      case BonusRowType.views:
        return AnalyticsPanel(imageId: imageId);
      case BonusRowType.terminal:
        return TerminalPanel(imageId: imageId);
      default:
        return div([text('Singleton panel type not configured.')]);
    }
  }

  Component _buildPagePanel(Map<String, dynamic> pageData) {
    final imageId = pageData['imageId'] ?? '';
    if (imageId.isEmpty) return div([]);

    if (activePanel == BonusRowType.textReader) {
      return TextReaderPanel(imageId: imageId, fanzineId: fanzineId);
    } else if (activePanel == BonusRowType.comments) {
      return CommentsPanel(imageId: imageId);
    } else if (activePanel == BonusRowType.editText || activePanel == BonusRowType.linkedText) {
      return EditTextPanel(imageId: imageId, fanzineId: fanzineId);
    } else if (activePanel == BonusRowType.entities) {
      return EntitiesPanel(imageId: imageId, fanzineId: fanzineId, isEditingMode: false);
    } else if (activePanel == BonusRowType.rawText) {
      return RawTextPanel(imageId: imageId);
    } else if (activePanel == BonusRowType.indicia) {
      return IndiciaPanel(fanzineId: fanzineId, isEditingMode: false);
    } else if (activePanel == BonusRowType.credits) {
      return CreditsPanel(imageId: imageId);
    } else if (activePanel == BonusRowType.newPage) {
      return PublisherTextPanel(imageId: imageId, fanzineId: fanzineId);
    } else {
      return div([text('Panel type not yet implemented in web column.')]);
    }
  }
}