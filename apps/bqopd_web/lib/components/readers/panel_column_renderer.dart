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
import '../panels/publisher_panel.dart';
import '../panels/terminal_panel.dart';
import '../panels/terminal_admin_panel.dart';
import '../panels/hashtag_panel.dart';
import '../panels/settings_panel.dart';
import '../panels/share_panel.dart';

/// Renders the third column for Desktop view in Jaspr.
/// Directly maps each active tool to its dedicated ColumnPanel implementation,
/// forwarding active target highlights and pre-rendered static text HTML
/// for synchronized instant reading.
class PanelColumnRenderer extends StatelessComponent {
  final String fanzineId;
  final String? shortCode;
  final String? fanzineTitle;
  final String? masterIndicia;
  final int? startMonth;
  final int? startYear;
  final bool hasCover;
  final List<Map<String, dynamic>> pages;
  final Map<String, Map<String, dynamic>> preloadedImageStats;
  final BonusRowType activePanel;
  final bool isEditingMode;
  final VoidCallback onClose;
  final int targetIndex;
  final void Function(int pageIndex)? onPageCardTap;

  const PanelColumnRenderer({
    required this.fanzineId,
    this.shortCode,
    this.fanzineTitle,
    this.masterIndicia,
    this.startMonth,
    this.startYear,
    this.hasCover = true,
    required this.pages,
    this.preloadedImageStats = const {},
    required this.activePanel,
    this.isEditingMode = false,
    required this.onClose,
    this.targetIndex = 0,
    this.onPageCardTap,
    super.key,
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
    if (activePanel == BonusRowType.terminalAdmin) title = "Terminal Game Admin";
    if (activePanel == BonusRowType.publisher) title = "Publisher";
    if (activePanel == BonusRowType.shareOptions) title = "Share & Print Spread";

    final bool isSingleton = activePanel == BonusRowType.settings ||
        activePanel == BonusRowType.youtube ||
        activePanel == BonusRowType.terminal ||
        activePanel == BonusRowType.terminalAdmin ||
        activePanel == BonusRowType.analyticsDashboard ||
        activePanel == BonusRowType.publisher;

    if (isSingleton) {
      final int activePageIdx =
          (targetIndex > 0 && targetIndex <= pages.length) ? targetIndex - 1 : 0;
      final activePageData =
          pages.isNotEmpty ? pages[activePageIdx] : <String, dynamic>{};
      final imageId = activePageData['imageId']?.toString() ?? '';
      return SingleWindowColumnLayout(
        title: title,
        onClose: onClose,
        child: _buildSingletonWidget(imageId),
      );
    }

    // Top Header Widget: Display the unified Issue Place Map above the per-page cards
    final Component? headerWidget = (activePanel == BonusRowType.entities)
        ? EntitiesColumnPanelHeader(fanzineId: fanzineId, pages: pages)
        : null;

    final int targetPageIndex =
        (targetIndex > 0 && targetIndex <= pages.length) ? targetIndex - 1 : 0;

    return MultiPageColumnLayout(
      title: title,
      pages: pages,
      headerWidget: headerWidget,
      onClose: onClose,
      targetPageIndex: targetPageIndex,
      onPageCardTap: onPageCardTap,
      indexedPageBuilder: (pageIndex, pageData) =>
          _buildPagePanel(pageIndex, pageData, targetPageIndex),
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
      case BonusRowType.terminalAdmin:
        return const TerminalAdminColumnPanel();
      case BonusRowType.settings:
        return const SettingsColumnPanel();
      case BonusRowType.publisher:
        return const PublisherColumnPanel();
      default:
        return div([Component.text('Singleton panel type not configured.')]);
    }
  }

  Component _buildPagePanel(
    int pageIndex,
    Map<String, dynamic> pageData,
    int targetPageIndex,
  ) {
    final imageId = pageData['imageId'] ?? '';
    if (activePanel == BonusRowType.shareOptions) {
      return ShareColumnPanel(
        fanzineId: fanzineId,
        shortCode: shortCode,
        fanzineTitle: fanzineTitle,
        masterIndicia: masterIndicia,
        startMonth: startMonth,
        startYear: startYear,
        hasCover: hasCover,
        pages: pages,
        pageData: pageData,
        pageIndex: pageIndex,
        preloadedImageStats: preloadedImageStats,
        isTarget: pageIndex == targetPageIndex,
      );
    }

    if (imageId.isEmpty) return div([]);

    switch (activePanel) {
      case BonusRowType.textReader:
        final preloadedHtml =
            (pageData['textHtml'] ?? pageData['text_html'])?.toString();
        final preloadedText = pageData['text']?.toString();
        return TextReaderColumnPanel(
          imageId: imageId,
          fanzineId: fanzineId,
          preloadedHtml: preloadedHtml,
          preloadedText: preloadedText,
        );
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
        return IndiciaColumnPanel(
          fanzineId: fanzineId,
          isEditingMode: isEditingMode,
        );
      case BonusRowType.credits:
        return CreditsColumnPanel(imageId: imageId);
      case BonusRowType.newPage:
        return PublisherTextColumnPanel(imageId: imageId, fanzineId: fanzineId);
      default:
        return div([Component.text('Panel type not implemented in column view.')]);
    }
  }
}