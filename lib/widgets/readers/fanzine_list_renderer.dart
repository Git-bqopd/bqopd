import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import '../../services/view_service.dart';
import '../../services/engagement_service.dart';
import '../../services/user_provider.dart';
import '../../components/social_toolbar.dart';
import '../../utils/link_parser.dart';
import '../comment_item.dart';
import '../stats_table.dart';

class FanzineListRenderer extends StatefulWidget {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ScrollController scrollController;
  final ViewService viewService;
  final Function(int)? onOpenGrid;
  final int initialIndex;
  final Function(Widget drawerContent)? onExternalDrawerRequest;

  const FanzineListRenderer({
    super.key,
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    required this.scrollController,
    required this.viewService,
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

  final EngagementService _engagementService = EngagementService();
  final Map<int, TextEditingController> _commentControllers = {};

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
    super.dispose();
  }

  void _handleTextToggle(int index, String text) {
    if (widget.onExternalDrawerRequest != null) {
      widget.onExternalDrawerRequest!(_buildSidebarText(text));
    } else {
      setState(() {
        _openTextRows[index] = !(_openTextRows[index] ?? false);
        if (_openTextRows[index] == true) { _openCommentRows[index] = false; _openViewRows[index] = false; }
      });
    }
  }

  void _handleCommentToggle(int index, String imageId) {
    if (widget.onExternalDrawerRequest != null) {
      widget.onExternalDrawerRequest!(_buildSidebarComments(index, imageId));
    } else {
      setState(() {
        _openCommentRows[index] = !(_openCommentRows[index] ?? false);
        if (_openCommentRows[index] == true) { _openTextRows[index] = false; _openViewRows[index] = false; }
      });
    }
  }

  void _handleViewToggle(int index, String imageId) {
    if (widget.onExternalDrawerRequest != null) {
      widget.onExternalDrawerRequest!(_buildSidebarViews(imageId));
    } else {
      setState(() {
        _openViewRows[index] = !(_openViewRows[index] ?? false);
        if (_openViewRows[index] == true) { _openTextRows[index] = false; _openCommentRows[index] = false; }
      });
    }
  }

  Widget _buildSidebarText(String text) => _SidebarWrapper(title: "TRANSCRIPTION", child: SelectableText.rich(LinkParser.renderLinks(context, text, baseStyle: const TextStyle(fontSize: 14, fontFamily: 'Georgia'))));

  Widget _buildSidebarComments(int pageIndex, String imageId) {
    final controller = _commentControllers.putIfAbsent(pageIndex, () => TextEditingController());
    return _SidebarWrapper(title: "COMMENTS", child: Column(children: [Expanded(child: _CommentList(imageId: imageId, service: _engagementService)), _CommentInput(controller: controller, onSend: () => _submitComment(pageIndex, imageId))]));
  }

  Widget _buildSidebarViews(String imageId) {
    return _SidebarWrapper(title: "ANALYTICS", child: StatsTable(contentId: imageId, viewService: widget.viewService));
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
    return ListView.separated(
      controller: widget.scrollController,
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
          isTextOpen: _openTextRows[pageIndex] ?? false,
          isCommentsOpen: _openCommentRows[pageIndex] ?? false,
          isViewsOpen: _openViewRows[pageIndex] ?? false,
          onToggleText: () => _handleTextToggle(pageIndex, pageData['text_processed'] ?? pageData['text'] ?? ''),
          onToggleComment: () => _handleCommentToggle(pageIndex, imageId),
          onToggleViews: () => _handleViewToggle(pageIndex, imageId),
          onOpenGrid: widget.onOpenGrid,
          submitComment: (imgId) => _submitComment(pageIndex, imgId),
          commentController: _commentControllers.putIfAbsent(pageIndex, () => TextEditingController()),
          viewService: widget.viewService,
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
  final bool isTextOpen;
  final bool isCommentsOpen;
  final bool isViewsOpen;
  final VoidCallback onToggleText;
  final VoidCallback onToggleComment;
  final VoidCallback onToggleViews;
  final Function(int)? onOpenGrid;
  final Function(String) submitComment;
  final TextEditingController commentController;
  final ViewService viewService;

  const _PageWidget({
    required this.index,
    required this.pageIndex,
    required this.pageData,
    required this.fanzineId,
    required this.fanzineTitle,
    required this.isTextOpen,
    required this.isCommentsOpen,
    required this.isViewsOpen,
    required this.onToggleText,
    required this.onToggleComment,
    required this.onToggleViews,
    this.onOpenGrid,
    required this.submitComment,
    required this.commentController,
    required this.viewService,
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
    if (imageId.isNotEmpty) {
      widget.viewService.recordView(
        imageId: imageId,
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
        Container(
          color: Colors.white,
          child: FutureBuilder<DocumentSnapshot>(
            future: imageId.isNotEmpty ? FirebaseFirestore.instance.collection('images').doc(imageId).get() : null,
            builder: (context, snapshot) {
              bool isGame = snapshot.hasData && (snapshot.data!.data() as Map?)?['isGame'] == true;
              return SocialToolbar(
                imageId: imageId,
                pageId: pageId,
                fanzineId: widget.fanzineId,
                pageNumber: widget.pageIndex + 1,
                isGame: isGame,
                onOpenGrid: widget.onOpenGrid != null ? () => widget.onOpenGrid!(widget.index) : null,
                onToggleComments: widget.onToggleComment,
                onToggleText: widget.onToggleText,
                onToggleViews: widget.onToggleViews,
              );
            },
          ),
        ),
        if (widget.isTextOpen) ...[
          const SizedBox(height: verticalGap),
          _BonusRowWrapper(color: const Color(0xFFFDFBF7), child: SelectableText.rich(LinkParser.renderLinks(context, widget.pageData['text_processed'] ?? widget.pageData['text'] ?? '', baseStyle: const TextStyle(fontSize: 14, fontFamily: 'Georgia')))),
        ],
        if (widget.isCommentsOpen) ...[
          const SizedBox(height: verticalGap),
          _BonusRowWrapper(color: Colors.white, child: Column(children: [ConstrainedBox(constraints: const BoxConstraints(maxHeight: 300), child: _CommentList(imageId: imageId, service: EngagementService())), _CommentInput(controller: widget.commentController, onSend: () => widget.submitComment(imageId))])),
        ],
        if (widget.isViewsOpen) ...[
          const SizedBox(height: verticalGap),
          _BonusRowWrapper(color: Colors.grey[50]!, child: StatsTable(contentId: imageId, viewService: widget.viewService)),
        ],
      ],
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
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Container(padding: const EdgeInsets.all(16), color: Colors.grey[200], child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2))), Expanded(child: Padding(padding: const EdgeInsets.all(16), child: child))]);
}

class _CommentList extends StatelessWidget {
  final String imageId; final EngagementService service;
  const _CommentList({required this.imageId, required this.service});
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
  void initState() { super.initState(); _currentUrl = widget.imageUrl; if ((_currentUrl == null || _currentUrl!.isEmpty) && widget.storagePath != null) _resolveUrl(); }
  Future<void> _resolveUrl() async { try { final url = await FirebaseStorage.instance.ref(widget.storagePath!).getDownloadURL(); if (mounted) setState(() => _currentUrl = url); } catch (_) {} }
  @override
  Widget build(BuildContext context) => _currentUrl == null || _currentUrl!.isEmpty ? const Center(child: CircularProgressIndicator()) : Image.network(_currentUrl!, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)));
}