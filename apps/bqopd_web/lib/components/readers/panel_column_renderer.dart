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
import '../panels/hashtag_panel.dart';
import '../panels/settings_panel.dart';

/// Renders the third column for Desktop view in Jaspr.
/// Directly maps each active tool to its dedicated ColumnPanel implementation.
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
    if (activePanel == BonusRowType.tags) title = "Hashtags & Community Tags";
    if (activePanel == BonusRowType.settings) title = "Toolbar Settings";
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
        return YoutubeColumnPanel(imageId: imageId);
      case BonusRowType.analyticsDashboard:
      case BonusRowType.views:
        return AnalyticsColumnPanel(
          fanzineId: fanzineId,
          imageId: imageId,
          pages: pages,
        );
      case BonusRowType.terminal:
        return TerminalColumnPanel(imageId: imageId);
      case BonusRowType.settings:
        return const SettingsColumnPanel();
      default:
        return div([text('Singleton panel type not configured.')]);
    }
  }

  Component _buildPagePanel(Map<String, dynamic> pageData) {
    final imageId = pageData['imageId'] ?? '';
    if (imageId.isEmpty) return div([]);

    switch (activePanel) {
      case BonusRowType.textReader:
        return TextReaderColumnPanel(imageId: imageId, fanzineId: fanzineId);
      case BonusRowType.comments:
        return CommentsColumnPanel(imageId: imageId, fanzineId: fanzineId);
      case BonusRowType.editText:
      case BonusRowType.linkedText:
        return EditTextColumnPanel(imageId: imageId, fanzineId: fanzineId);
      case BonusRowType.entities:
        return EntitiesColumnPanel(imageId: imageId, fanzineId: fanzineId);
      case BonusRowType.tags:
        return HashtagColumnPanel(imageId: imageId);
      case BonusRowType.rawText:
        return RawTextColumnPanel(imageId: imageId);
      case BonusRowType.indicia:
        return IndiciaColumnPanel(fanzineId: fanzineId, isEditingMode: isEditingMode);
      case BonusRowType.credits:
        return CreditsColumnPanel(imageId: imageId);
      case BonusRowType.newPage:
        return PublisherTextColumnPanel(imageId: imageId, fanzineId: fanzineId);
      default:
        return div([text('Panel type not implemented in column view.')]);
    }
  }
}