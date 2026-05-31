import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../social_toolbar.dart';
import '../panels/panel_container.dart';
import '../panels/text_reader_panel.dart';
import '../panels/comments_panel.dart';
import '../panels/hashtag_panel.dart';
import '../panels/master_text_panel.dart';
import '../panels/linked_text_panel.dart';
import '../panels/entities_panel.dart';
import '../panels/raw_text_panel.dart';
import '../panels/indicia_panel.dart';
import '../panels/credits_panel.dart';
import '../panels/youtube_panel.dart';
import '../panels/analytics_panel.dart';

class ReaderPageItem extends StatefulComponent {
  final String fanzineId;
  final Map<String, dynamic> pageData;
  final int pageIndex;
  final VoidCallback? onOpenGrid;
  final Map<String, dynamic>? initialImageStats;
  final Set<String> likedImageIds; // Pass downs down
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool isEditingMode;

  const ReaderPageItem({
    required this.fanzineId,
    required this.pageData,
    required this.pageIndex,
    this.onOpenGrid,
    this.initialImageStats,
    required this.likedImageIds,
    this.authState,
    this.authBloc,
    this.isEditingMode = false,
    super.key,
  });

  @override
  State<ReaderPageItem> createState() => _ReaderPageItemState();
}

class _ReaderPageItemState extends State<ReaderPageItem> {
  BonusRowType? _activePanel;

  void _handleTogglePanel(BonusRowType type) {
    setState(() {
      _activePanel = (_activePanel == type) ? null : type;
    });
  }

  @override
  Component build(BuildContext context) {
    final String imageId = component.pageData['imageId'] ?? '';
    final String? url = component.pageData['listUrl'] ?? component.pageData['imageUrl'];

    return div(classes: 'reader-list-item flex-col w-full', [
      div(classes: 'aspect-5-8 bg-gray-100 flex-col items-center justify-center', [
        if (url != null && url.isNotEmpty)
          img(
              src: url,
              classes: 'w-full h-full',
              attributes: {
                'style': 'object-fit: contain;',
                'loading': 'lazy',
              }
          )
        else
          p(classes: 'text-gray text-xs', [text('Processing Assets...')])
      ]),

      div(classes: 'bg-white', [
        SocialToolbar(
          imageId: imageId,
          fanzineId: component.fanzineId,
          onOpenGrid: component.onOpenGrid,
          activeBonusRow: _activePanel,
          onToggleBonusRow: _handleTogglePanel,
          likedImageIds: component.likedImageIds, // Pass downs down
          initialImageStats: component.initialImageStats,
          authState: component.authState,
          authBloc: component.authBloc,
          isEditingMode: component.isEditingMode,
        ),

        // AVOID rendering the redundant vertical SettingsPanel container when the settings tab is active
        if (_activePanel != null && _activePanel != BonusRowType.settings)
          _buildPanelContent(imageId),
      ])
    ]);
  }

  Component _buildPanelContent(String imageId) {
    Component inner;
    String title = "";

    switch (_activePanel!) {
      case BonusRowType.textReader:
        title = ""; // Omit the 'READER' text
        inner = TextReaderPanel(imageId: imageId);
        break;
      case BonusRowType.comments:
        title = "Comments";
        inner = CommentsPanel(imageId: imageId);
        break;
      case BonusRowType.tags:
        title = "Hashtags & Voting";
        inner = HashtagPanel(imageId: imageId);
        break;
      case BonusRowType.rawText:
        title = "Raw OCR Text";
        inner = RawTextPanel(imageId: imageId);
        break;
      case BonusRowType.masterText:
        title = ""; // Omit the 'CORRECTED TEXT EDITOR' title
        inner = MasterTextPanel(imageId: imageId, fanzineId: component.fanzineId);
        break;
      case BonusRowType.linkedText:
        title = ""; // Omit the 'WIKI-LINK EDITOR' title
        inner = LinkedTextPanel(imageId: imageId, fanzineId: component.fanzineId);
        break;
      case BonusRowType.entities:
        title = ""; // Omit 'PAGE ENTITIES' text
        inner = EntitiesPanel(imageId: imageId, fanzineId: component.fanzineId, isEditingMode: component.isEditingMode);
        break;
      case BonusRowType.indicia:
        title = "Issue Indicia";
        inner = IndiciaPanel(fanzineId: component.fanzineId, isEditingMode: component.isEditingMode);
        break;
      case BonusRowType.credits:
        title = "Creators";
        inner = CreditsPanel(imageId: imageId);
        break;
      case BonusRowType.youtube:
        title = "Video Resource";
        inner = YoutubePanel(imageId: imageId);
        break;
      case BonusRowType.analyticsDashboard:
        title = "Analytics Dashboard";
        inner = AnalyticsPanel(imageId: imageId);
        break;
      case BonusRowType.terminal:
        title = "Terminal Game";
        inner = div([
          p(classes: 'text-center text-sm text-gray p-6 italic', [
            text('CA Combat Terminal is optimized only for mobile application contexts.')
          ])
        ]);
        break;
      default:
        return div([]);
    }

    return PanelContainer(
      title: title,
      type: _activePanel!,
      child: inner,
    );
  }
}