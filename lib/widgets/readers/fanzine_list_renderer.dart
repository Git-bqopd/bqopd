import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../services/view_service.dart';
import '../../services/engagement_service.dart';
import '../../services/user_provider.dart';
import '../../components/social_toolbar.dart';
import '../../utils/link_parser.dart';
import '../comment_item.dart';
import '../stats_table.dart';
import '../youtube_player_widget.dart';
import '../templates/basic_text_template.dart';

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
  final Map<int, bool> _openTextRows = {};
  final Map<int, bool> _openCommentRows = {};
  final Map<int, bool> _openViewRows = {};
  final Map<int, bool> _openCreditRows = {};
  final Map<int, bool> _openYouTubeRows = {};

  final EngagementService _engagementService = EngagementService();
  final Map<int, TextEditingController> _commentControllers = {};

  // Global Font Size Notifier for the reader session
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
    for (var c in _commentControllers.values) c.dispose();
    _fontSizeNotifier.dispose();
    super.dispose();
  }

  // --- TOGGLE HANDLERS ---

  void _handleTextToggle(int index, String text, String imageId) {
    if (widget.onExternalDrawerRequest != null) {
      widget.onExternalDrawerRequest!(_buildSidebarText(text, imageId));
    } else {
      setState(() {
        _openTextRows[index] = !(_openTextRows[index] ?? false);
        if (_openTextRows[index] == true) {
          _openCommentRows[index] = false;
          _openViewRows[index] = false;
          _openCreditRows[index] = false;
          _openYouTubeRows[index] = false;
        }
      });
    }
  }

  void _handleCommentToggle(int index, String imageId) {
    if (widget.onExternalDrawerRequest != null) {
      widget.onExternalDrawerRequest!(_buildSidebarComments(index, imageId));
    } else {
      setState(() {
        _openCommentRows[index] = !(_openCommentRows[index] ?? false);
        if (_openCommentRows[index] == true) {
          _openTextRows[index] = false;
          _openViewRows[index] = false;
          _openCreditRows[index] = false;
          _openYouTubeRows[index] = false;
        }
      });
    }
  }

  void _handleViewToggle(int index, String imageId) {
    if (widget.onExternalDrawerRequest != null) {
      widget.onExternalDrawerRequest!(_buildSidebarViews(imageId));
    } else {
      setState(() {
        _openViewRows[index] = !(_openViewRows[index] ?? false);
        if (_openViewRows[index] == true) {
          _openTextRows[index] = false;
          _openCommentRows[index] = false;
          _openCreditRows[index] = false;
          _openYouTubeRows[index] = false;
        }
      });
    }
  }

  void _handleCreditToggle(int index, String imageId) {
    if (widget.onExternalDrawerRequest != null) {
      widget.onExternalDrawerRequest!(_buildSidebarCredits(imageId));
    } else {
      setState(() {
        _openCreditRows[index] = !(_openCreditRows[index] ?? false);
        if (_openCreditRows[index] == true) {
          _openTextRows[index] = false;
          _openCommentRows[index] = false;
          _openViewRows[index] = false;
          _openYouTubeRows[index] = false;
        }
      });
    }
  }

  void _handleYouTubeToggle(int index, String imageId) {
    if (widget.onExternalDrawerRequest != null) {
      widget.onExternalDrawerRequest!(_buildSidebarYouTube(imageId));
    } else {
      setState(() {
        _openYouTubeRows[index] = !(_openYouTubeRows[index] ?? false);
        if (_openYouTubeRows[index] == true) {
          _openTextRows[index] = false;
          _openCommentRows[index] = false;
          _openViewRows[index] = false;
          _openCreditRows[index] = false;
        }
      });
    }
  }

  // --- SIDEBAR BUILDERS ---

  Widget _buildSidebarText(String text, String imageId) {
    return _SidebarWrapper(
      title: "", // Removed "TRANSCRIPTION" header
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

  Widget _buildSidebarComments(int pageIndex, String imageId) {
    final controller = _commentControllers.putIfAbsent(pageIndex, () => TextEditingController());
    return _SidebarWrapper(title: "COMMENTS", child: Column(children: [Expanded(child: _CommentList(imageId: imageId, service: _engagementService)), _CommentInput(controller: controller, onSend: () => _submitComment(pageIndex, imageId))]));
  }

  Widget _buildSidebarViews(String imageId) {
    return _SidebarWrapper(title: "ANALYTICS", child: StatsTable(contentId: imageId, viewService: widget.viewService));
  }

  Widget _buildSidebarCredits(String imageId) {
    return _SidebarWrapper(title: "ARCHIVAL METADATA & CREDITS", child: _CreditsEditorWidget(imageId: imageId));
  }

  Widget _buildSidebarYouTube(String imageId) {
    return _SidebarWrapper(title: "VIDEO", child: YouTubePlayerWidget(imageId: imageId));
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
        if (index == 0) return widget.headerWidget;

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        final imageId = pageData['imageId'] ?? '';

        return _PageWidget(
          index: index,
          pageIndex: pageIndex,
          pageData: pageData,
          fanzineId: widget.fanzineId,
          fanzineTitle: _fanzineTitle,
          isEditingMode: widget.isEditingMode,
          onToggleEditMode: widget.onToggleEditMode,
          isTextOpen: _openTextRows[pageIndex] ?? false,
          isCommentsOpen: _openCommentRows[pageIndex] ?? false,
          isViewsOpen: _openViewRows[pageIndex] ?? false,
          isCreditsOpen: _openCreditRows[pageIndex] ?? false,
          isYouTubeOpen: _openYouTubeRows[pageIndex] ?? false,
          onToggleText: (actualText) => _handleTextToggle(pageIndex, actualText, imageId),
          onToggleComment: () => _handleCommentToggle(pageIndex, imageId),
          onToggleViews: () => _handleViewToggle(pageIndex, imageId),
          onToggleCredits: () => _handleCreditToggle(pageIndex, imageId),
          onToggleYouTube: () => _handleYouTubeToggle(pageIndex, imageId),
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
  final String fanzineId;
  final String fanzineTitle;
  final bool isEditingMode;
  final VoidCallback onToggleEditMode;
  final bool isTextOpen;
  final bool isCommentsOpen;
  final bool isViewsOpen;
  final bool isCreditsOpen;
  final bool isYouTubeOpen;
  final Function(String actualText) onToggleText;
  final VoidCallback onToggleComment;
  final VoidCallback onToggleViews;
  final VoidCallback onToggleCredits;
  final VoidCallback onToggleYouTube;
  final Function(int)? onOpenGrid;
  final Function(String) submitComment;
  final TextEditingController commentController;
  final ViewService viewService;
  final ValueNotifier<double> fontSizeNotifier;

  const _PageWidget({
    required this.index,
    required this.pageIndex,
    required this.pageData,
    required this.fanzineId,
    required this.fanzineTitle,
    required this.isEditingMode,
    required this.onToggleEditMode,
    required this.isTextOpen,
    required this.isCommentsOpen,
    required this.isViewsOpen,
    required this.isCreditsOpen,
    required this.isYouTubeOpen,
    required this.onToggleText,
    required this.onToggleComment,
    required this.onToggleViews,
    required this.onToggleCredits,
    required this.onToggleYouTube,
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
    final String pageId = widget.pageData['__id'] ?? '';
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
    final String pageId = widget.pageData['__id'] ?? 'unknown';
    final String imageId = widget.pageData['imageId'] ?? '';
    const double verticalGap = 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 0.625,
          child: Container(
            color: Colors.grey[100],
            child: _PageImage(imageUrl: widget.pageData['imageUrl'], storagePath: widget.pageData['storagePath']),
          ),
        ),
        const SizedBox(height: verticalGap),

        FutureBuilder<DocumentSnapshot>(
          future: imageId.isNotEmpty ? FirebaseFirestore.instance.collection('images').doc(imageId).get() : null,
          builder: (context, snapshot) {
            bool isGame = false;
            String? youtubeId;
            String actualText = "";

            if (snapshot.hasData && snapshot.data?.data() != null) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              isGame = data['isGame'] == true;
              youtubeId = data['youtubeId'] as String?;
              actualText = data['text_processed'] ?? data['text'] ?? '';
            }

            return Column(
              children: [
                Container(
                  color: Colors.white,
                  child: SocialToolbar(
                    imageId: imageId,
                    pageId: pageId,
                    fanzineId: widget.fanzineId,
                    pageNumber: widget.pageIndex + 1,
                    isGame: isGame,
                    youtubeId: youtubeId,
                    isEditingMode: widget.isEditingMode,
                    onToggleEditMode: widget.onToggleEditMode,
                    onOpenGrid: widget.onOpenGrid != null ? () => widget.onOpenGrid!(widget.index) : null,
                    onToggleComments: widget.onToggleComment,
                    onToggleText: () => widget.onToggleText(actualText),
                    onToggleViews: widget.onToggleViews,
                    onToggleCredits: widget.onToggleCredits,
                    onToggleYouTube: widget.onToggleYouTube,
                  ),
                ),
                if (widget.isTextOpen) ...[
                  const SizedBox(height: verticalGap),
                  _BonusRowWrapper(
                    color: const Color(0xFFFDFBF7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.isEditingMode) _FontSizeSlider(fontSizeNotifier: widget.fontSizeNotifier),
                        widget.isEditingMode
                            ? _InlineTextEditor(imageId: imageId, initialText: actualText)
                            : ValueListenableBuilder<double>(
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
                if (widget.isYouTubeOpen) ...[
                  const SizedBox(height: verticalGap),
                  _BonusRowWrapper(color: Colors.black, child: YouTubePlayerWidget(imageId: imageId)),
                ],
                if (widget.isCommentsOpen) ...[
                  const SizedBox(height: verticalGap),
                  _BonusRowWrapper(color: Colors.white, child: Column(children: [ConstrainedBox(constraints: const BoxConstraints(maxHeight: 300), child: _CommentList(imageId: imageId, service: EngagementService())), _CommentInput(controller: widget.commentController, onSend: () => widget.submitComment(imageId))])),
                ],
                if (widget.isViewsOpen) ...[
                  const SizedBox(height: verticalGap),
                  _BonusRowWrapper(color: Colors.grey[50]!, child: StatsTable(contentId: imageId, viewService: widget.viewService)),
                ],
                if (widget.isCreditsOpen) ...[
                  const SizedBox(height: verticalGap),
                  _BonusRowWrapper(color: Colors.white, child: _CreditsEditorWidget(imageId: imageId)),
                ],
              ],
            );
          },
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
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.black54,
                    inactiveTrackColor: Colors.black12,
                    thumbColor: Colors.black,
                  ),
                  child: Slider(
                    value: size,
                    min: 12.0,
                    max: 48.0,
                    divisions: 36,
                    onChanged: (val) => fontSizeNotifier.value = val,
                  ),
                );
              },
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: fontSizeNotifier,
            builder: (context, size, _) {
              return Text("${size.toInt()}px", style: const TextStyle(fontSize: 10, color: Colors.grey));
            },
          ),
        ],
      ),
    );
  }
}

class _BonusRowWrapper extends StatelessWidget {
  final Widget child; final Color color;
  const _BonusRowWrapper({super.key, required this.child, required this.color});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color, border: Border(top: BorderSide(color: Colors.grey.shade200), bottom: BorderSide(color: Colors.grey.shade200))), child: child);
}

class _SidebarWrapper extends StatelessWidget {
  final String title; final Widget child;
  const _SidebarWrapper({super.key, required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (title.isNotEmpty)
      Container(padding: const EdgeInsets.all(16), color: Colors.grey[200], child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2))),
    Expanded(child: Padding(padding: const EdgeInsets.all(16), child: child))
  ]);
}

class _CommentList extends StatelessWidget {
  final String imageId; final EngagementService service;
  const _CommentList({super.key, required this.imageId, required this.service});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(stream: service.getCommentsStream(imageId), builder: (context, snap) {
    if (!snap.hasData) return const SizedBox();
    final sortedDocs = snap.data!.docs.map((d) { final m = d.data() as Map<String, dynamic>; m['_id'] = d.id; return m; }).toList();
    sortedDocs.sort((a, b) { final aT = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(); final bT = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(); return aT.compareTo(bT); });
    if (sortedDocs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No comments yet.")));
    return ListView.separated(shrinkWrap: true, physics: const ClampingScrollPhysics(), itemCount: sortedDocs.length, separatorBuilder: (c, i) => const Divider(height: 1, color: Colors.black12), itemBuilder: (c, i) => CommentItem(data: sortedDocs[i]));
  });
}

class _CommentInput extends StatelessWidget {
  final TextEditingController controller; final VoidCallback onSend;
  const _CommentInput({super.key, required this.controller, required this.onSend});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: "Add a comment...", isDense: true, border: OutlineInputBorder()))), IconButton(icon: const Icon(Icons.send), onPressed: onSend)]));
}

class _PageImage extends StatefulWidget {
  final String? imageUrl; final String? storagePath;
  const _PageImage({super.key, this.imageUrl, this.storagePath});
  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  String? _currentUrl;
  @override
  void initState() { super.initState(); _currentUrl = widget.imageUrl; if ((_currentUrl == null || _currentUrl!.isEmpty) && widget.storagePath != null) _resolveUrl(); }
  Future<void> _resolveUrl() async { try { final url = await FirebaseStorage.instance.ref(widget.storagePath!).getDownloadURL(); if (mounted) setState(() => _currentUrl = url); } catch (_) {} }
  @override
  Widget build(BuildContext context) => _currentUrl == null || _currentUrl!.isEmpty ? const Center(child: CircularProgressIndicator()) : Image.network(_currentUrl!, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)));
}

class _CreditsEditorWidget extends StatefulWidget {
  final String imageId;
  const _CreditsEditorWidget({super.key, required this.imageId});

  @override
  State<_CreditsEditorWidget> createState() => _CreditsEditorWidgetState();
}

class _CreditsEditorWidgetState extends State<_CreditsEditorWidget> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();
  final TextEditingController _indiciaController = TextEditingController();

  List<Map<String, dynamic>> _creators = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (widget.imageId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('images').doc(widget.imageId).get();
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _indiciaController.text = data['indicia'] ?? '';
          final rawCreators = data['creators'] as List<dynamic>? ?? [];
          _creators = rawCreators.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error loading credits: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addCreator() async {
    final input = _searchController.text.trim();
    final role = _roleController.text.trim();
    if (input.isEmpty || role.isEmpty) return;

    setState(() => _isSaving = true);

    String? uid;
    String name = input;

    if (input.startsWith('@')) {
      final handle = input.substring(1).toLowerCase();
      try {
        final query = await FirebaseFirestore.instance.collection('Users').where('username', isEqualTo: handle).limit(1).get();
        if (query.docs.isNotEmpty) {
          uid = query.docs.first.id;
          final data = query.docs.first.data();
          name = data['displayName'] ?? data['username'] ?? input;
        }
      } catch (e) {
        debugPrint("Error looking up user: $e");
      }
    }

    setState(() {
      _creators.add({
        'uid': uid,
        'name': name,
        'role': role,
      });
      _searchController.clear();
      _roleController.clear();
      _isSaving = false;
    });
  }

  Future<void> _saveData() async {
    if (widget.imageId.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({
        'indicia': _indiciaController.text.trim(),
        'creators': _creators,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archival metadata saved!')));
      }
    } catch (e) {
      debugPrint("Error saving metadata: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _roleController.dispose();
    _indiciaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Indicia / Copyright Notice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: _indiciaController,
          maxLines: 3,
          style: const TextStyle(fontSize: 12, fontFamily: 'Georgia'),
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: "Enter copyright boilerplate..."),
        ),
        const SizedBox(height: 20),

        const Text("Creators", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        if (_creators.isEmpty)
          const Text("No creators added.", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Colors.grey)),

        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _creators.length,
          itemBuilder: (context, index) {
            final creator = _creators[index];
            final String role = (creator['role'] ?? 'Creator').toString().toUpperCase();
            final String fallbackName = (creator['name'] ?? 'Unknown').toString().toUpperCase();
            final String? uid = creator['uid'];

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 55,
                      child: Text(
                        role,
                        style: const TextStyle(fontSize: 9, color: Colors.black54, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text("|", style: TextStyle(fontSize: 12, color: Colors.black12)),
                  ),
                  Expanded(
                    child: _buildCreatorInfo(uid, fallbackName),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _creators.removeAt(index)),
                    child: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 20),
                  )
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        const Text("Add Co-Creator", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                    hintText: "Search user by @handle...",
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder()
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _roleController,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                    hintText: "Role (e.g. Inker)",
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder()
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isSaving ? null : _addCreator,
              icon: const Icon(Icons.add_circle, color: Color(0xFFF1B255), size: 32),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          ],
        ),

        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveData,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF1B255),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSaving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text("SAVE CREDITS & INDICIA", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
      ],
    );
  }

  Widget _buildCreatorInfo(String? uid, String fallbackName) {
    if (uid == null || uid.isEmpty) {
      return Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withOpacity(0.1)),
              ),
              child: Center(child: Text(fallbackName.isNotEmpty ? fallbackName[0] : '?', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fallbackName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text("Guest Contributor", style: TextStyle(fontSize: 8, color: Colors.black.withOpacity(0.4), fontStyle: FontStyle.italic)),
                ],
              ),
            )
          ]
      );
    }

    return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('Users').doc(uid).get(),
        builder: (context, snap) {
          String name = fallbackName;
          String handle = "fetching...";
          String? photoUrl;
          bool userExists = false;

          if (snap.hasData && snap.data!.exists) {
            userExists = true;
            final data = snap.data!.data() as Map<String, dynamic>;
            name = (data['displayName'] ?? data['username'] ?? fallbackName).toString().toUpperCase();
            handle = "@${data['username'] ?? 'user'}".toLowerCase();
            photoUrl = data['photoUrl'];
          } else if (snap.connectionState == ConnectionState.done) {
            handle = "@unknown";
          }

          return Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black.withOpacity(0.1)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photoUrl != null
                      ? ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ]),
                      child: Image.network(photoUrl, fit: BoxFit.cover)
                  )
                      : Center(child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (userExists && handle != "@unknown") {
                        context.goNamed('shortlink', pathParameters: {'code': handle.substring(1)});
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(handle, style: TextStyle(fontSize: 8, color: Colors.black.withOpacity(0.4))),
                      ],
                    ),
                  ),
                ),
              ]
          );
        }
    );
  }
}

class _InlineTextEditor extends StatefulWidget {
  final String imageId;
  final String initialText;

  const _InlineTextEditor({super.key, required this.imageId, required this.initialText});

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late TextEditingController _controller;
  bool _isSaving = false;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void didUpdateWidget(covariant _InlineTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId) {
      _controller.text = widget.initialText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({
        'text': _controller.text,
        'text_processed': _controller.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text saved!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("TEXT EDITOR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _showPreview = !_showPreview),
                  icon: Icon(_showPreview ? Icons.visibility_off : Icons.visibility, size: 16),
                  label: Text(_showPreview ? "Hide Preview" : "Show Preview", style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save, size: 16),
                  label: const Text("Save", style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            )
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          maxLines: null,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: "Enter text transcription...",
            border: OutlineInputBorder(),
            fillColor: Colors.white,
            filled: true,
          ),
          style: const TextStyle(fontFamily: 'Courier', fontSize: 14),
        ),
        if (_showPreview) ...[
          const SizedBox(height: 16),
          const Text("LIVE PREVIEW (2000x3200 Scale)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final pagesOfBlocks = BasicTextTemplate.paginateContent(_controller.text);
                if (pagesOfBlocks.isEmpty) return const SizedBox(height: 200, child: Center(child: Text("No content")));
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pagesOfBlocks.length,
                  separatorBuilder: (c, i) => const Divider(height: 32, thickness: 2),
                  itemBuilder: (context, index) {
                    return Column(
                      children: [
                        Text("Page ${index + 1}", style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        AspectRatio(
                          aspectRatio: 2000 / 3200,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: BasicTextTemplate(
                              columns: pagesOfBlocks[index],
                              showOverlay: true,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ]
      ],
    );
  }
}