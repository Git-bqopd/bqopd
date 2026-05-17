import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../social_toolbar.dart';
import '../panels/panel_container.dart';
import '../panels/text_reader_panel.dart';
import '../panels/comments_panel.dart';
import '../panels/hashtag_panel.dart';
import '../panels/settings_panel.dart'; // NEW

class ReaderPageItem extends StatefulComponent {
  final String fanzineId;
  final Map<String, dynamic> pageData;
  final int pageIndex;
  final VoidCallback? onOpenGrid;

  const ReaderPageItem({
    required this.fanzineId,
    required this.pageData,
    required this.pageIndex,
    this.onOpenGrid,
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
      // Page Image Layer
      div(classes: 'aspect-5-8 bg-gray-100 flex-col items-center justify-center', [
        if (url != null && url.isNotEmpty)
          img(src: url, classes: 'w-full h-full', attributes: {'style': 'object-fit: contain;'})
        else
          p(classes: 'text-gray text-xs', [text('Processing Assets...')])
      ]),

      // Interaction Layer
      div(classes: 'bg-white', [
        SocialToolbar(
          imageId: imageId,
          fanzineId: component.fanzineId,
          onOpenGrid: component.onOpenGrid,
          activeBonusRow: _activePanel,
          onToggleBonusRow: _handleTogglePanel,
        ),

        if (_activePanel != null)
          _buildPanelContent(imageId),
      ])
    ]);
  }

  Component _buildPanelContent(String imageId) {
    Component inner;
    String title = "";

    switch (_activePanel!) {
      case BonusRowType.textReader:
        title = "Reader";
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
      case BonusRowType.settings: // FIXED: Now handling settings panel
        title = "Toolbar Settings";
        inner = SettingsPanel();
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