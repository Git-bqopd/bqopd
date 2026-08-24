import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../social_toolbar.dart';
import '../panels/panel_container.dart';
import '../panels/text_reader_panel.dart';
import '../panels/comments_panel.dart';
import '../panels/hashtag_panel.dart';
import '../panels/edit_text_panel.dart';
import '../panels/entities_panel.dart';
import '../panels/raw_text_panel.dart';
import '../panels/indicia_panel.dart';
import '../panels/credits_panel.dart';
import '../panels/youtube_panel.dart';
import '../panels/analytics_panel.dart';
import '../panels/publisher_text_panel.dart';
import '../panels/terminal_panel.dart';

class ReaderPageItem extends StatefulComponent {
  final String fanzineId;
  final Map<String, dynamic> pageData;
  final int pageIndex;
  final VoidCallback? onOpenGrid;
  final Map<String, dynamic>? initialImageStats;
  final Set<String> likedImageIds;
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool isEditingMode;
  final BonusRowType? activeGlobalPanel;
  final ValueChanged<BonusRowType>? onTogglePanel;

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
    this.activeGlobalPanel,
    this.onTogglePanel,
    super.key,
  });

  @override
  State<ReaderPageItem> createState() => _ReaderPageItemState();
}

class _ReaderPageItemState extends State<ReaderPageItem> {
  String _templateTextValue = '';
  dynamic _imgDataUnsub;

  @override
  void initState() {
    super.initState();
    _listenToTemplateImageContents();
  }

  @override
  void didUpdateComponent(ReaderPageItem oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.pageData['imageId'] != component.pageData['imageId']) {
      _listenToTemplateImageContents();
    }
  }

  @override
  void dispose() {
    _imgDataUnsub?.cancel();
    super.dispose();
  }

  void _listenToTemplateImageContents() {
    _imgDataUnsub?.cancel();
    _imgDataUnsub = null;
    final imageId = component.pageData['imageId'];
    final templateId = component.pageData['templateId'];
    if (imageId == null || imageId.isEmpty || templateId != 'basic_text') return;

    _imgDataUnsub = fsListenDoc('images/$imageId', (String jsonStr) {
      try {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] == true && mounted) {
          setState(() {
            _templateTextValue = doc['data']['text_linked'] ?? doc['data']['text_corrected'] ?? doc['data']['text'] ?? '';
          });
        }
      } catch (_) {}
    });
  }

  void _handleTogglePanel(BonusRowType type) {
    if (component.onTogglePanel != null) {
      component.onTogglePanel!(type);
    }
  }

  @override
  Component build(BuildContext context) {
    final String imageId = component.pageData['imageId'] ?? '';
    final String? url = component.pageData['listUrl'] ?? component.pageData['imageUrl'];

    return div(
        classes: 'reader-list-item-card bg-white rounded-lg border border-gray-300 shadow-md mb-6 w-full flex-col overflow-hidden',
        attributes: const {
          'style': 'background-color: #ffffff; border: 1px solid #cbd5e1; border-radius: 8px; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08); overflow: hidden; margin-bottom: 24px; width: 100%; box-sizing: border-box;'
        },
        [
          // Top Card Section: Page Image Container
          div(
              classes: 'aspect-5-8 bg-gray-100 flex-col items-center justify-center border-b border-gray-200 w-full',
              attributes: const {
                'style': 'aspect-ratio: 5 / 8; background-color: #f1f5f9; display: flex; flex-direction: column; align-items: center; justify-content: center; border-bottom: 1px solid #e2e8f0; width: 100%;'
              },
              [
                if (url != null && url.isNotEmpty)
                  img(
                      src: url,
                      classes: 'w-full h-full',
                      attributes: const {
                        'style': 'width: 100%; height: 100%; object-fit: contain; -webkit-user-select: none; -moz-user-select: none; -ms-user-select: none; user-select: none; pointer-events: none;',
                        'draggable': 'false',
                        'loading': 'lazy',
                      }
                  )
                else
                  div(classes: 'flex-col gap-2 py-4 w-full h-full justify-center items-center p-8', [
                    div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'width: 80%; height: 16px; margin-bottom: 12px;'}),
                    div([], classes: 'skeleton-line medium shimmer-bg', attributes: const {'style': 'width: 90%; height: 16px; margin-bottom: 12px;'}),
                    div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'width: 70%; height: 16px; margin-bottom: 12px;'}),
                    div([], classes: 'skeleton-line short shimmer-bg', attributes: const {'style': 'width: 50%; height: 16px; margin-bottom: 12px;'}),
                  ])
              ]
          ),
          // Bottom Card Section: Social Toolbar + Social Panel (Stretches Card vertically when opened)
          div(
              classes: 'bg-white p-3 flex-col w-full',
              attributes: const {
                'style': 'background-color: #ffffff; padding: 12px; display: flex; flex-direction: column; width: 100%; box-sizing: border-box;'
              },
              [
                SocialToolbar(
                  imageId: imageId,
                  fanzineId: component.fanzineId,
                  onOpenGrid: component.onOpenGrid,
                  activeBonusRow: component.activeGlobalPanel,
                  onToggleBonusRow: _handleTogglePanel,
                  likedImageIds: component.likedImageIds,
                  initialImageStats: component.initialImageStats,
                  authState: component.authState,
                  authBloc: component.authBloc,
                  isEditingMode: component.isEditingMode,
                ),
                if (component.activeGlobalPanel != null && component.activeGlobalPanel != BonusRowType.settings)
                  _buildPanelContent(imageId, component.activeGlobalPanel!),
              ]
          )
        ]
    );
  }

  Component _buildPanelContent(String imageId, BonusRowType activePanel) {
    Component inner;
    String title = "";
    switch (activePanel) {
      case BonusRowType.textReader:
        title = "";
        inner = TextReaderPanel(imageId: imageId, fanzineId: component.fanzineId);
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
      case BonusRowType.editText:
      case BonusRowType.linkedText:
        title = "";
        inner = EditTextPanel(imageId: imageId, fanzineId: component.fanzineId);
        break;
      case BonusRowType.entities:
        title = "";
        inner = EntitiesPanel(imageId: imageId, fanzineId: component.fanzineId, isEditingMode: false);
        break;
      case BonusRowType.indicia:
        title = "Issue Indicia";
        inner = IndiciaPanel(fanzineId: component.fanzineId, isEditingMode: false);
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
      case BonusRowType.newPage:
        title = "New Page Text Editor";
        inner = PublisherTextPanel(imageId: imageId, fanzineId: component.fanzineId);
        break;
      case BonusRowType.terminal:
        title = "Combat Terminal";
        inner = TerminalPanel(imageId: imageId);
        break;
      default:
        return div([]);
    }

    return PanelContainer(
      title: title,
      type: activePanel,
      child: inner,
    );
  }
}