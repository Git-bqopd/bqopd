import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../services/view_service.dart';
import '../../services/engagement_service.dart';
import '../../services/user_provider.dart';
import '../../utils/link_parser.dart';
import '../../services/user_bootstrap.dart';
import '../../services/username_service.dart';
import '../../models/reader_tool.dart';

import '../comment_item.dart';
import '../stats_table.dart';
import '../youtube_player_widget.dart';
import '../templates/basic_text_template.dart';
import '../templates/calendar_template.dart';
import '../calendar_editor_widget.dart';
import '../hashtag_bar.dart';
import '../../components/dynamic_social_toolbar.dart';

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
      Widget drawerContent = const SizedBox();
      switch (rowType) {
        case BonusRowType.textReader: drawerContent = _buildSidebarText(actualText, imageId); break;
        case BonusRowType.tags: drawerContent = _buildSidebarTags(imageId); break;
        case BonusRowType.ocr: drawerContent = _buildSidebarOCR(imageId, pageId); break;
        case BonusRowType.entities: drawerContent = _buildSidebarEntities(imageId, actualText); break;
        case BonusRowType.publisher:
          if (templateId != null && templateId.startsWith('calendar')) {
            drawerContent = CalendarEditorWidget(folioId: widget.fanzineId);
          } else {
            drawerContent = _buildSidebarPublisher(actualText, imageId);
          }
          break;
        case BonusRowType.comments: drawerContent = _buildSidebarComments(pageIndex, imageId); break;
        case BonusRowType.views: drawerContent = _buildSidebarViews(imageId); break;
        case BonusRowType.credits: drawerContent = _buildSidebarCredits(pageIndex, imageId); break;
        case BonusRowType.youtube: drawerContent = _buildSidebarYouTube(imageId); break;
        case BonusRowType.indicia: drawerContent = _buildSidebarIndicia(imageId); break;
        case BonusRowType.editDetails: drawerContent = const Text("Edit Details not implemented yet"); break;
      }
      widget.onExternalDrawerRequest!(drawerContent);
    } else {
      setState(() {
        if (_activeBonusRows[pageIndex] == rowType) {
          _activeBonusRows[pageIndex] = null;
        } else {
          _activeBonusRows[pageIndex] = rowType;
        }
      });
    }
  }

  Widget _buildSidebarText(String text, String imageId) {
    return _SidebarWrapper(
      title: "",
      child: widget.isEditingMode
          ? _InlineTextEditor(imageId: imageId, initialText: text)
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FontSizeSlider(fontSizeNotifier: _fontSizeNotifier),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: _fontSizeNotifier,
              builder: (context, size, _) {
                return SelectableText.rich(
                  LinkParser.renderLinks(context, text, baseStyle: TextStyle(fontSize: size, fontFamily: 'Georgia')),
                  textAlign: TextAlign.justify,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTags(String imageId) {
    return _SidebarWrapper(
      title: "HASHTAGS & VOTING",
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('images').doc(imageId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final tags = data['tags'] as Map<String, dynamic>? ?? {};
          return SingleChildScrollView(
            child: HashtagBar(imageId: imageId, tags: tags),
          );
        },
      ),
    );
  }

  Widget _buildSidebarOCR(String imageId, String pageId) {
    return _SidebarWrapper(
      title: "OCR PIPELINE (EGG EDITOR)",
      child: _OCRStatusView(fanzineId: widget.fanzineId, pageId: pageId, imageId: imageId),
    );
  }

  Widget _buildSidebarEntities(String imageId, String text) {
    return _SidebarWrapper(
      title: "PAGE ENTITIES",
      child: _PageEntitiesView(text: text),
    );
  }

  Widget _buildSidebarPublisher(String text, String imageId) {
    return _SidebarWrapper(
      title: "PUBLISHER (CHICKEN EDITOR)",
      child: _InlineTextEditor(imageId: imageId, initialText: text, showPublisherPreview: true),
    );
  }

  Widget _buildSidebarComments(int pageIndex, String imageId) {
    final controller = _commentControllers.putIfAbsent(pageIndex, () => TextEditingController());
    return _SidebarWrapper(title: "COMMENTS", child: Column(children: [Expanded(child: _CommentList(imageId: imageId, service: _engagementService)), _CommentInput(controller: controller, onSend: () => _submitComment(pageIndex, imageId))]));
  }

  Widget _buildSidebarViews(String imageId) {
    return _SidebarWrapper(title: "ANALYTICS", child: StatsTable(contentId: imageId, viewService: widget.viewService));
  }

  Widget _buildSidebarCredits(int index, String imageId) {
    return _SidebarWrapper(title: "ARCHIVAL METADATA & CREDITS", child: _CreditsEditorWidget(imageId: imageId));
  }

  Widget _buildSidebarYouTube(String imageId) {
    return _SidebarWrapper(title: "VIDEO", child: YouTubePlayerWidget(imageId: imageId));
  }

  Widget _buildSidebarIndicia(String imageId) {
    return _SidebarWrapper(title: "ISSUE INDICIA", child: _MasterIndiciaWidget(fanzineId: widget.fanzineId, isEditingMode: widget.isEditingMode));
  }

  Future<void> _submitComment(int pageIndex, String imageId) async {
    final controller = _commentControllers[pageIndex];
    if (controller == null || controller.text.trim().isEmpty) return;
    final text = controller.text.trim();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    controller.clear();
    if (widget.onExternalDrawerRequest == null) FocusScope.of(context).unfocus();
    await _engagementService.addComment(imageId: imageId, fanzineId: widget.fanzineId, fanzineTitle: _fanzineTitle, text: text, displayName: userProvider.userProfile?['displayName'], username: userProvider.userProfile?['username']);
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

        // FIXED: Removed the unused imageId and pageId variables here to clear warnings
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
                  Map<String, dynamic> tags = {};

                  if (snapshot.hasData && snapshot.data?.data() != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    isGame = data['isGame'] == true;
                    youtubeId = data['youtubeId'] as String?;
                    actualText = data['text'] ?? data['text_processed'] ?? data['text_raw'] ?? '';
                    tags = data['tags'] as Map<String, dynamic>? ?? {};
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

                      if (widget.activeBonusRow == BonusRowType.textReader) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(
                          color: const Color(0xFFFDFBF7),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _FontSizeSlider(fontSizeNotifier: widget.fontSizeNotifier),
                              ValueListenableBuilder<double>(
                                valueListenable: widget.fontSizeNotifier,
                                builder: (context, size, _) {
                                  return SelectableText.rich(
                                    LinkParser.renderLinks(context, actualText, baseStyle: TextStyle(fontSize: size, fontFamily: 'Georgia')),
                                    textAlign: TextAlign.justify,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (widget.activeBonusRow == BonusRowType.tags) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(
                          color: Colors.white,
                          child: HashtagBar(imageId: imageId, tags: tags),
                        ),
                      ],
                      if (widget.activeBonusRow == BonusRowType.ocr) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(
                            color: Colors.grey[50]!,
                            child: _OCRStatusView(fanzineId: widget.fanzineId, pageId: pageId, imageId: imageId)
                        ),
                      ],
                      if (widget.activeBonusRow == BonusRowType.entities) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(
                            color: Colors.white,
                            child: _PageEntitiesView(text: actualText)
                        ),
                      ],
                      if (widget.activeBonusRow == BonusRowType.publisher) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(
                            color: Colors.white,
                            child: templateId != null && templateId.startsWith('calendar')
                                ? CalendarEditorWidget(folioId: widget.fanzineId)
                                : _InlineTextEditor(imageId: imageId, initialText: actualText, showPublisherPreview: true)
                        ),
                      ],
                      if (widget.activeBonusRow == BonusRowType.youtube) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(color: Colors.black, child: YouTubePlayerWidget(imageId: imageId)),
                      ],
                      if (widget.activeBonusRow == BonusRowType.comments) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(color: Colors.white, child: Column(children: [ConstrainedBox(constraints: const BoxConstraints(maxHeight: 300), child: _CommentList(imageId: imageId, service: EngagementService())), _CommentInput(controller: widget.commentController, onSend: () => widget.submitComment(imageId))])),
                      ],
                      if (widget.activeBonusRow == BonusRowType.views) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(color: Colors.grey[50]!, child: imageId.isNotEmpty ? StatsTable(contentId: imageId, viewService: widget.viewService) : const Text("Image not yet registered. Wait for OCR.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
                      ],
                      if (widget.activeBonusRow == BonusRowType.credits) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(color: Colors.white, child: _CreditsEditorWidget(imageId: imageId)),
                      ],
                      if (widget.activeBonusRow == BonusRowType.indicia) ...[
                        const SizedBox(height: verticalGap),
                        _BonusRowWrapper(color: Colors.white, child: _MasterIndiciaWidget(fanzineId: widget.fanzineId, isEditingMode: widget.isEditingMode)),
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

class _OCRStatusView extends StatelessWidget {
  final String fanzineId;
  final String pageId;
  final String imageId;
  const _OCRStatusView({required this.fanzineId, required this.pageId, required this.imageId});

  @override
  Widget build(BuildContext context) {
    if (fanzineId.isEmpty || pageId.isEmpty) {
      return const Text("Pipeline data unavailable (Missing Page ID).", style: TextStyle(color: Colors.red, fontSize: 12));
    }

    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()));
          final data = snap.data!.data() as Map<String, dynamic>?;
          if (data == null) return const Text("Page data missing.");

          final status = data['status'] ?? 'ready';
          final error = data['errorLog'];

          Color statusColor = Colors.grey;
          if (status == 'ocr_complete' || status == 'complete' || status == 'review_needed' || status == 'transcribed') statusColor = Colors.green;
          if (status == 'queued' || status == 'entity_queued') statusColor = Colors.orange;
          if (status == 'error') statusColor = Colors.red;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("OCR STATUS (EGG MODE)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  if (status == 'review_needed' || status == 'complete')
                    const Icon(Icons.check_circle, color: Colors.green, size: 14),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(status.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: statusColor)),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                const Text("Error Log:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                Text(error, style: TextStyle(fontSize: 10, color: Colors.red[700], fontFamily: 'Courier')),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 14, color: Colors.red),
                      label: const Text("Retry Transcription", style: TextStyle(color: Colors.red, fontSize: 11)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      onPressed: () {
                        FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').doc(pageId).update({
                          'status': 'queued',
                          'errorLog': FieldValue.delete()
                        });
                      }
                  ),
                )
              ],
              const SizedBox(height: 16),
              const Divider(),
              const Text("RAW EXTRACTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              if (imageId.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                  child: const Text("Image not registered yet. Waiting for initial pipeline run...", style: TextStyle(fontSize: 12, fontFamily: 'Courier', color: Colors.grey)),
                )
              else
                FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('images').doc(imageId).get(),
                    builder: (context, imgSnap) {
                      final raw = (imgSnap.data?.data() as Map?)?['text_raw'] ?? "Pending...";
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                        child: Text(raw, style: const TextStyle(fontSize: 12, fontFamily: 'Courier')),
                      );
                    }
                )
            ],
          );
        }
    );
  }
}

class _PageEntitiesView extends StatelessWidget {
  final String text;
  const _PageEntitiesView({required this.text});

  List<String> _parseEntities(String content) {
    final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
    final matches = regex.allMatches(content);
    final Set<String> results = {};
    for (final m in matches) {
      final name = m.group(1);
      if (name != null && name.isNotEmpty) results.add(name);
    }
    return results.toList();
  }

  @override
  Widget build(BuildContext context) {
    final entities = _parseEntities(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("DETECTED ENTITIES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        if (entities.isEmpty)
          const Text("No entity links found in page text.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entities.length,
            separatorBuilder: (c, i) => const Divider(height: 1),
            itemBuilder: (c, i) => _EntityRow(name: entities[i]),
          ),
      ],
    );
  }
}

class _FontSizeSlider extends StatelessWidget {
  final ValueNotifier<double> fontSizeNotifier;
  const _FontSizeSlider({required this.fontSizeNotifier});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          const Icon(Icons.format_size, size: 14, color: Colors.grey),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: fontSizeNotifier,
              builder: (context, size, _) {
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 14), activeTrackColor: Colors.black54, inactiveTrackColor: Colors.black12, thumbColor: Colors.black),
                  child: Slider(value: size, min: 12.0, max: 48.0, divisions: 36, onChanged: (val) => fontSizeNotifier.value = val),
                );
              },
            ),
          ),
          ValueListenableBuilder<double>(valueListenable: fontSizeNotifier, builder: (context, size, _) => Text("${size.toInt()}px", style: const TextStyle(fontSize: 10, color: Colors.grey))),
        ],
      ),
    );
  }
}

class _BonusRowWrapper extends StatelessWidget {
  final Widget child; final Color color;
  const _BonusRowWrapper({required this.child, required this.color});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color, border: Border(top: BorderSide(color: Colors.grey.shade200), bottom: BorderSide(color: Colors.grey.shade200))), child: child);
}

class _SidebarWrapper extends StatelessWidget {
  final String title; final Widget child;
  const _SidebarWrapper({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (title.isNotEmpty) Container(padding: const EdgeInsets.all(16), color: Colors.grey[200], child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2))),
    Expanded(child: Padding(padding: const EdgeInsets.all(16), child: child))
  ]);
}

class _CommentList extends StatelessWidget {
  final String imageId; final EngagementService service;
  const _CommentList({required this.imageId, required this.service});
  @override
  Widget build(BuildContext context) {
    if (imageId.isEmpty) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(stream: service.getCommentsStream(imageId), builder: (context, snap) {
      if (!snap.hasData) return const SizedBox();
      final sortedDocs = snap.data!.docs.map((d) { final m = d.data() as Map<String, dynamic>; m['_id'] = d.id; return m; }).toList();
      sortedDocs.sort((a, b) { final aT = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(); final bT = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(); return aT.compareTo(bT); });
      if (sortedDocs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No comments yet.")));
      return ListView.separated(shrinkWrap: true, physics: const ClampingScrollPhysics(), itemCount: sortedDocs.length, separatorBuilder: (c, i) => const Divider(height: 1, color: Colors.black12), itemBuilder: (c, i) => CommentItem(data: sortedDocs[i]));
    });
  }
}

class _CommentInput extends StatelessWidget {
  final TextEditingController controller; final VoidCallback onSend;
  const _CommentInput({required this.controller, required this.onSend});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: "Add a comment...", isDense: true, border: OutlineInputBorder()))), IconButton(icon: const Icon(Icons.send), onPressed: onSend)]));
}

class _PageImage extends StatefulWidget {
  final String? imageUrl; final String? storagePath;
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
  Widget build(BuildContext context) => _currentUrl == null || _currentUrl!.isEmpty ? const Center(child: CircularProgressIndicator()) : Image.network(_currentUrl!, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)));
}

class _CreditsEditorWidget extends StatefulWidget {
  final String imageId;
  const _CreditsEditorWidget({required this.imageId});
  @override
  State<_CreditsEditorWidget> createState() => _CreditsEditorWidgetState();
}

class _CreditsEditorWidgetState extends State<_CreditsEditorWidget> {
  final TextEditingController _sC = TextEditingController(), _rC = TextEditingController(), _iC = TextEditingController();
  List<Map<String, dynamic>> _creators = []; bool _loading = true, _saving = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (widget.imageId.isEmpty) { setState(() => _loading = false); return; }
    try {
      final doc = await FirebaseFirestore.instance.collection('images').doc(widget.imageId).get();
      if (doc.exists && mounted) {
        final d = doc.data() as Map<String, dynamic>;
        setState(() { _iC.text = d['indicia'] ?? ''; _creators = (d['creators'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(); _loading = false; });
      } else { setState(() => _loading = false); }
    } catch (_) { setState(() => _loading = false); }
  }
  Future<void> _save() async {
    if (widget.imageId.isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({
        'indicia': _iC.text.trim(),
        'creators': _creators
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (widget.imageId.isEmpty) return const Text("Image not yet registered.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text("Indicia / Copyright", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      TextField(controller: _iC, maxLines: 3, style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
      const SizedBox(height: 16),
      const Text("Creators", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ..._creators.map((c) => ListTile(dense: true, title: Text("${c['name']} (${c['role']})"), trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setState(() => _creators.remove(c))))),
      Row(children: [Expanded(child: TextField(controller: _sC, decoration: const InputDecoration(hintText: "@handle"))), const SizedBox(width: 8), Expanded(child: TextField(controller: _rC, decoration: const InputDecoration(hintText: "Role"))), IconButton(icon: const Icon(Icons.add), onPressed: () { if (_sC.text.isNotEmpty) setState(() => _creators.add({'name': _sC.text, 'role': _rC.text})); _sC.clear(); _rC.clear(); })]),
      ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? "Saving..." : "Save Metadata"))
    ]);
  }
}

class _InlineTextEditor extends StatefulWidget {
  final String imageId;
  final String initialText;
  final bool showPublisherPreview;

  const _InlineTextEditor({required this.imageId, required this.initialText, this.showPublisherPreview = false});
  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late TextEditingController _c; bool _s = false, _p = false;
  @override
  void initState() { super.initState(); _c = TextEditingController(text: widget.initialText); _p = widget.showPublisherPreview; }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (widget.imageId.isEmpty) return;
    setState(() => _s = true);
    try {
      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({'text': _c.text, 'text_processed': _c.text});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } finally {
      if (mounted) setState(() => _s = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (widget.imageId.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text("Waiting for OCR Pipeline to register this page before editing is allowed.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(widget.showPublisherPreview ? "CHICKEN EDITOR (PUBLISHER)" : "TEXT EDITOR", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        Row(children: [IconButton(icon: Icon(_p ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _p = !_p)), IconButton(icon: const Icon(Icons.save), onPressed: _s ? null : _save)])
      ]),
      TextField(controller: _c, maxLines: null, minLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), fillColor: Colors.white, filled: true), style: const TextStyle(fontFamily: 'Courier', fontSize: 14)),
      if (_p) ...[
        const SizedBox(height: 16),
        const Text("LIVE PREVIEW (2000x3200 SCALE)", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        AspectRatio(
            aspectRatio: 2000/3200,
            child: Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                child: FittedBox(
                    child: BasicTextTemplate(columns: BasicTextTemplate.paginateContent(_c.text)[0])
                )
            )
        )
      ]
    ]);
  }
}

class _EntityRow extends StatelessWidget {
  final String name;
  const _EntityRow({required this.name});

  @override
  Widget build(BuildContext context) {
    final handle = normalizeHandle(name);
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usernames').doc(handle).snapshots(),
      builder: (context, snapshot) {
        Widget statusWidget;
        if (!snapshot.hasData) {
          statusWidget = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String linkText = '/$handle';
          if (data['isAlias'] == true) linkText = '/$handle -> /${data['redirect'] ?? 'unknown'}';
          statusWidget = Text(linkText, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline));
        } else {
          statusWidget = Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => _createProfile(context, name), child: const Text("Create", style: TextStyle(color: Colors.green, fontSize: 11))),
            TextButton(onPressed: () => _createAlias(context, name), child: const Text("Alias", style: TextStyle(color: Colors.orange, fontSize: 11))),
          ]);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
            statusWidget,
          ]),
        );
      },
    );
  }

  Future<void> _createProfile(BuildContext context, String name) async {
    String first = name; String last = "";
    if (name.contains(' ')) { final parts = name.split(' '); first = parts.first; last = parts.sublist(1).join(' '); }
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Editor Widget");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final target = await showDialog<String>(context: context, builder: (c) {
      final controller = TextEditingController();
      return AlertDialog(title: Text("Create Alias for '$name'"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Enter EXISTING username (target):"), TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")), TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))]);
    });
    if (target == null || target.isEmpty) return;
    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}

class _MasterIndiciaWidget extends StatefulWidget {
  final String fanzineId;
  final bool isEditingMode;
  const _MasterIndiciaWidget({required this.fanzineId, required this.isEditingMode});

  @override
  State<_MasterIndiciaWidget> createState() => _MasterIndiciaWidgetState();
}

class _MasterIndiciaWidgetState extends State<_MasterIndiciaWidget> {
  final TextEditingController _c = TextEditingController();
  List<Map<String, dynamic>> _assembledCreators = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).get();
    if (doc.exists && mounted) {
      setState(() {
        _c.text = doc.data()?['masterIndicia'] ?? '';
        _assembledCreators = (doc.data()?['masterCreators'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).update({
        'masterIndicia': _c.text.trim(),
        'masterCreators': _assembledCreators,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _autoAssemble() async {
    setState(() => _loading = true);
    try {
      final pagesSnap = await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).collection('pages').orderBy('pageNumber').get();
      List<String> assembledIndicia = [];
      List<Map<String, dynamic>> allCreators = [];
      Set<String> seenCreatorKeys = {};

      for (var p in pagesSnap.docs) {
        final pData = p.data();
        final imageId = pData['imageId'];
        if (imageId != null && imageId.toString().isNotEmpty) {
          final imgDoc = await FirebaseFirestore.instance.collection('images').doc(imageId).get();
          if (imgDoc.exists) {
            final imgData = imgDoc.data() as Map<String, dynamic>;

            final creators = imgData['creators'] as List? ?? [];
            for (var c in creators) {
              final cMap = Map<String, dynamic>.from(c as Map);
              final key = "${cMap['uid']}_${cMap['name']}_${cMap['role']}";
              if (!seenCreatorKeys.contains(key)) {
                seenCreatorKeys.add(key);
                allCreators.add(cMap);
              }
            }

            final imgIndicia = imgData['indicia'] as String?;
            if (imgIndicia != null && imgIndicia.trim().isNotEmpty) {
              assembledIndicia.add(imgIndicia.trim());
            }
          }
        }
      }

      setState(() {
        _c.text = assembledIndicia.join('\n\n').trim();
        _assembledCreators = allCreators;
      });

    } catch (e) {
      debugPrint("Assemble error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (!widget.isEditingMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("ISSUE INDICIA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(_c.text.isEmpty ? "No indicia available for this issue." : _c.text, style: const TextStyle(fontSize: 12, fontFamily: 'Georgia', height: 1.5)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("INDICIA EDITOR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ElevatedButton.icon(
              onPressed: _autoAssemble,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text("Auto-Assemble Meta", style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
            )
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _c,
          maxLines: null,
          minLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Master Indicia text..."),
          style: const TextStyle(fontSize: 12, fontFamily: 'Georgia', height: 1.5),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? "Saving..." : "Save Master Meta"),
          ),
        )
      ],
    );
  }
}