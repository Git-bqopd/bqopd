import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../services/view_service.dart';
import '../../services/engagement_service.dart';
import '../../services/user_provider.dart';
import '../../models/reader_tool.dart';

import '../../components/dynamic_social_toolbar.dart';
import '../templates/calendar_template.dart';
import '../reader_panels/panel_container.dart';
import '../reader_panels/panel_factory.dart';

class FanzineListRenderer extends StatefulWidget {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ItemScrollController itemScrollController;
  final ViewService viewService;
  final bool isEditingMode;
  final VoidCallback onToggleEditMode;
  final Function(int)? onOpenGrid;
  final int initialIndex;
  final Function(Widget drawerContent)? onExternalDrawerRequest;

  const FanzineListRenderer({
    super.key,
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    required this.itemScrollController,
    required this.viewService,
    this.isEditingMode = false,
    required this.onToggleEditMode,
    this.onOpenGrid,
    this.initialIndex = 0,
    this.onExternalDrawerRequest,
  });

  @override
  State<FanzineListRenderer> createState() => _FanzineListRendererState();
}

class _FanzineListRendererState extends State<FanzineListRenderer> {
  final Map<int, BonusRowType?> _activeBonusRows = {};
  final EngagementService _engagementService = EngagementService();
  final Map<int, TextEditingController> _commentControllers = {};
  final ValueNotifier<double> _fontSizeNotifier = ValueNotifier(16.0);

  String _fanzineTitle = '...';

  @override
  void initState() {
    super.initState();
    _fetchFanzineMeta();
  }

  Future<void> _fetchFanzineMeta() async {
    final doc = await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).get();
    if (doc.exists && mounted) {
      setState(() => _fanzineTitle = doc.data()?['title'] ?? 'Untitled');
    }
  }

  @override
  void dispose() {
    for (var c in _commentControllers.values) {
      c.dispose();
    }
    _fontSizeNotifier.dispose();
    super.dispose();
  }

  void _handleBonusRowToggle(int pageIndex, BonusRowType rowType, String imageId, String pageId, String actualText, String? templateId) {
    if (widget.onExternalDrawerRequest != null) {
      // Desktop Sidebar Mode
      Widget drawerContent = PanelFactory.buildPanelContent(
        type: rowType,
        imageId: imageId,
        fanzineId: widget.fanzineId,
        pageId: pageId,
        actualText: actualText,
        templateId: templateId,
        isEditingMode: widget.isEditingMode,
        viewService: widget.viewService,
        engagementService: _engagementService,
        commentController: _commentControllers.putIfAbsent(pageIndex, () => TextEditingController()),
        onSubmitComment: () => _submitComment(pageIndex, imageId),
        fontSizeNotifier: _fontSizeNotifier,
      );

      widget.onExternalDrawerRequest!(
        PanelContainer(
          title: PanelFactory.getTitle(rowType),
          isInline: false,
          child: drawerContent,
        ),
      );
    } else {
      // Mobile Inline Mode
      setState(() {
        if (_activeBonusRows[pageIndex] == rowType) {
          _activeBonusRows[pageIndex] = null;
        } else {
          _activeBonusRows[pageIndex] = rowType;
        }
      });
    }
  }

  Future<void> _submitComment(int pageIndex, String imageId) async {
    final controller = _commentControllers[pageIndex];
    if (controller == null || controller.text.trim().isEmpty) return;
    final text = controller.text.trim();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    controller.clear();
    if (widget.onExternalDrawerRequest == null) FocusScope.of(context).unfocus();

    await _engagementService.addComment(
        imageId: imageId,
        fanzineId: widget.fanzineId,
        fanzineTitle: _fanzineTitle,
        text: text,
        displayName: userProvider.userProfile?['displayName'],
        username: userProvider.userProfile?['username']
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollablePositionedList.separated(
      itemScrollController: widget.itemScrollController,
      initialScrollIndex: widget.initialIndex,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.pages.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 48),
      itemBuilder: (context, index) {
        if (index == 0) {
          return widget.headerWidget;
        }

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        final String? templateId = pageData['templateId'];

        return _PageWidget(
          index: index,
          pageIndex: pageIndex,
          pageData: pageData,
          templateId: templateId,
          fanzineId: widget.fanzineId,
          fanzineTitle: _fanzineTitle,
          isEditingMode: widget.isEditingMode,
          onToggleEditMode: widget.onToggleEditMode,
          activeBonusRow: _activeBonusRows[pageIndex],
          onToggleBonusRow: (rowType, actualText, currentImgId, currentPgId, currentTplId) {
            _handleBonusRowToggle(pageIndex, rowType, currentImgId, currentPgId, actualText, currentTplId);
          },
          onOpenGrid: widget.onOpenGrid,
          submitComment: (imgId) => _submitComment(pageIndex, imgId),
          commentController: _commentControllers.putIfAbsent(pageIndex, () => TextEditingController()),
          viewService: widget.viewService,
          fontSizeNotifier: _fontSizeNotifier,
        );
      },
    );
  }
}

class _PageWidget extends StatefulWidget {
  final int index;
  final int pageIndex;
  final Map<String, dynamic> pageData;
  final String? templateId;
  final String fanzineId;
  final String fanzineTitle;
  final bool isEditingMode;
  final VoidCallback onToggleEditMode;
  final BonusRowType? activeBonusRow;
  final Function(BonusRowType rowType, String actualText, String imageId, String pageId, String? templateId) onToggleBonusRow;
  final Function(int)? onOpenGrid;
  final Function(String) submitComment;
  final TextEditingController commentController;
  final ViewService viewService;
  final ValueNotifier<double> fontSizeNotifier;

  const _PageWidget({
    required this.index,
    required this.pageIndex,
    required this.pageData,
    this.templateId,
    required this.fanzineId,
    required this.fanzineTitle,
    required this.isEditingMode,
    required this.onToggleEditMode,
    required this.activeBonusRow,
    required this.onToggleBonusRow,
    this.onOpenGrid,
    required this.submitComment,
    required this.commentController,
    required this.viewService,
    required this.fontSizeNotifier,
  });

  @override
  State<_PageWidget> createState() => _PageWidgetState();
}

class _PageWidgetState extends State<_PageWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final String imageId = widget.pageData['imageId'] ?? '';
    final String pageId = widget.pageData['id'] ?? widget.pageData['__id'] ?? '';
    if (imageId.isNotEmpty) {
      widget.viewService.recordView(
        imageId: imageId,
        pageId: pageId,
        fanzineId: widget.fanzineId,
        fanzineTitle: widget.fanzineTitle,
        type: ViewType.list,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final String pageId = widget.pageData['id'] ?? widget.pageData['__id'] ?? '';
    final String imageId = widget.pageData['imageId'] ?? '';
    final String? templateId = widget.templateId;
    const double verticalGap = 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 0.625,
          child: Container(
            color: Colors.grey[100],
            child: templateId == 'calendar_left'
                ? CalendarPageRenderer(isLeft: true, folioId: widget.fanzineId)
                : templateId == 'calendar_right'
                ? CalendarPageRenderer(isLeft: false, folioId: widget.fanzineId)
                : _PageImage(imageUrl: widget.pageData['imageUrl'], storagePath: widget.pageData['storagePath']),
          ),
        ),
        const SizedBox(height: verticalGap),

        StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).snapshots(),
            builder: (context, fzSnapshot) {
              final fzData = fzSnapshot.data?.data() as Map<String, dynamic>?;
              final indiciaPageId = fzData?['indiciaPageId'];
              final isIndiciaPage = pageId == indiciaPageId;

              return StreamBuilder<DocumentSnapshot>(
                stream: imageId.isNotEmpty ? FirebaseFirestore.instance.collection('images').doc(imageId).snapshots() : null,
                builder: (context, snapshot) {
                  bool isGame = false;
                  String? youtubeId;
                  String actualText = "";

                  if (snapshot.hasData && snapshot.data?.data() != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    isGame = data['isGame'] == true;
                    youtubeId = data['youtubeId'] as String?;
                    actualText = data['text'] ?? data['text_processed'] ?? data['text_raw'] ?? '';
                  }

                  return Column(
                    children: [
                      Container(
                        color: Colors.white,
                        child: DynamicSocialToolbar(
                          imageId: imageId,
                          pageId: pageId,
                          fanzineId: widget.fanzineId,
                          pageNumber: widget.pageIndex + 1,
                          isGame: isGame,
                          youtubeId: youtubeId,
                          isEditingMode: widget.isEditingMode,
                          isIndiciaPage: isIndiciaPage,
                          onOpenGrid: widget.onOpenGrid != null ? () => widget.onOpenGrid!(widget.index) : null,
                          activeBonusRow: widget.activeBonusRow,
                          onToggleBonusRow: (rowType) => widget.onToggleBonusRow(rowType, actualText, imageId, pageId, templateId),
                        ),
                      ),

                      // MAGIC HAPPENS HERE: We replaced 500 lines of switch statements with 20 lines of Factory injection!
                      if (widget.activeBonusRow != null) ...[
                        const SizedBox(height: verticalGap),
                        PanelContainer(
                          title: '', // Inline doesn't use title
                          isInline: true,
                          inlineColor: PanelFactory.getInlineColor(widget.activeBonusRow!),
                          child: PanelFactory.buildPanelContent(
                            type: widget.activeBonusRow!,
                            imageId: imageId,
                            fanzineId: widget.fanzineId,
                            pageId: pageId,
                            actualText: actualText,
                            templateId: templateId,
                            isEditingMode: widget.isEditingMode,
                            viewService: widget.viewService,
                            engagementService: EngagementService(),
                            commentController: widget.commentController,
                            onSubmitComment: () => widget.submitComment(imageId),
                            fontSizeNotifier: widget.fontSizeNotifier,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            }
        ),
      ],
    );
  }
}

class _PageImage extends StatefulWidget {
  final String? imageUrl;
  final String? storagePath;

  const _PageImage({this.imageUrl, this.storagePath});

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    if (widget.storagePath != null && widget.storagePath!.isNotEmpty) {
      _resolveUrl();
    } else {
      _currentUrl = widget.imageUrl;
    }
  }

  Future<void> _resolveUrl() async {
    try {
      final url = await FirebaseStorage.instance.ref(widget.storagePath!).getDownloadURL();
      if (mounted) setState(() => _currentUrl = url);
    } catch (_) {
      if (mounted) setState(() => _currentUrl = widget.imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUrl == null || _currentUrl!.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Image.network(
        _currentUrl!,
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey))
    );
  }
}