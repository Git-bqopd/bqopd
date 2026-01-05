import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/view_service.dart';
import '../../services/engagement_service.dart';
import '../../components/social_toolbar.dart';
import '../../utils/link_parser.dart';

class FanzineListRenderer extends StatefulWidget {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ScrollController scrollController;
  final ViewService viewService;
  final Function(int)? onOpenGrid;
  final int initialIndex;

  const FanzineListRenderer({
    super.key,
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    required this.scrollController,
    required this.viewService,
    this.onOpenGrid,
    this.initialIndex = 0,
  });

  @override
  State<FanzineListRenderer> createState() => _FanzineListRendererState();
}

class _FanzineListRendererState extends State<FanzineListRenderer> {
  final Map<int, bool> _openTextDrawers = {};
  final Map<int, bool> _openCommentDrawers = {};
  final EngagementService _engagementService = EngagementService();
  final Map<int, TextEditingController> _commentControllers = {};

  @override
  void initState() {
    super.initState();
    // Logic for scrolling to initial index is handled by the controller passed from parent
    // or by the GridView's deterministic rendering.
  }

  void _toggleTextDrawer(int index) {
    setState(() {
      final isOpen = _openTextDrawers[index] ?? false;
      _openTextDrawers[index] = !isOpen;
      if (_openTextDrawers[index] == true) _openCommentDrawers[index] = false;
    });
  }

  void _toggleCommentDrawer(int index) {
    setState(() {
      final isOpen = _openCommentDrawers[index] ?? false;
      _openCommentDrawers[index] = !isOpen;
      if (_openCommentDrawers[index] == true) _openTextDrawers[index] = false;
    });
  }

  Future<void> _submitComment(int pageIndex, String pageId) async {
    final controller = _commentControllers[pageIndex];
    if (controller == null || controller.text.trim().isEmpty) return;

    final text = controller.text.trim();
    controller.clear();
    FocusScope.of(context).unfocus();

    try {
      await _engagementService.addComment(
        fanzineId: widget.fanzineId,
        pageId: pageId,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void dispose() {
    for (var c in _commentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // REVERTING TO GRIDVIEW.BUILDER (Single Column)
    // This matches the legacy `fanzine_single_view.dart` implementation exactly.
    // It enforces a strict aspect ratio, making scroll offsets deterministic.
    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1, // Single Column
        childAspectRatio: 0.625, // 5:8 Ratio (Matches Grid Renderer)
        mainAxisSpacing: 30.0,
      ),
      // Pre-load a large number of items to prevent lazy-loading delay
      // during rapid scrolling or switching.
      cacheExtent: 5000.0,
      itemCount: widget.pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Header fits naturally in the grid cell
          return widget.headerWidget;
        }

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        // Using AutomaticKeepAlive to ensure state persists
        return _KeepAlivePageItem(
          index: index,
          pageIndex: pageIndex,
          pageData: pageData,
          fanzineId: widget.fanzineId,
          isTextOpen: _openTextDrawers[pageIndex] ?? false,
          isCommentsOpen: _openCommentDrawers[pageIndex] ?? false,
          onToggleText: () => _toggleTextDrawer(pageIndex),
          onToggleComment: () => _toggleCommentDrawer(pageIndex),
          onOpenGrid: widget.onOpenGrid,
          commentController: _commentControllers.putIfAbsent(
              pageIndex, () => TextEditingController()),
          onSubmitComment: _submitComment,
          engagementService: _engagementService,
        );
      },
    );
  }
}

class _KeepAlivePageItem extends StatefulWidget {
  final int index;
  final int pageIndex;
  final Map<String, dynamic> pageData;
  final String fanzineId;
  final bool isTextOpen;
  final bool isCommentsOpen;
  final VoidCallback onToggleText;
  final VoidCallback onToggleComment;
  final Function(int)? onOpenGrid;
  final TextEditingController commentController;
  final Function(int, String) onSubmitComment;
  final EngagementService engagementService;

  const _KeepAlivePageItem({
    required this.index,
    required this.pageIndex,
    required this.pageData,
    required this.fanzineId,
    required this.isTextOpen,
    required this.isCommentsOpen,
    required this.onToggleText,
    required this.onToggleComment,
    required this.onOpenGrid,
    required this.commentController,
    required this.onSubmitComment,
    required this.engagementService,
  });

  @override
  State<_KeepAlivePageItem> createState() => _KeepAlivePageItemState();
}

class _KeepAlivePageItemState extends State<_KeepAlivePageItem> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Forces the item to stay in memory

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for KeepAlive

    final imageUrl = widget.pageData['imageUrl'] as String?;
    final storagePath = widget.pageData['storagePath'] as String?;
    final imageId = widget.pageData['imageId'] as String?;
    final pageId = widget.pageData['__id'];
    final String pageText = widget.pageData['text_processed'] ?? widget.pageData['text'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Image Area (Expanded to fill available space in the Grid Cell)
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: _PageImage(imageUrl: imageUrl, storagePath: storagePath),
          ),
        ),

        // Toolbar
        Container(
          color: Colors.white,
          child: imageId != null
              ? FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('images').doc(imageId).get(),
            builder: (context, snapshot) {
              bool isGame = false;
              if (snapshot.hasData && snapshot.data!.exists) {
                isGame = (snapshot.data!.data() as Map<String, dynamic>)['isGame'] == true;
              }
              return SocialToolbar(
                imageId: imageId,
                pageId: pageId,
                fanzineId: widget.fanzineId,
                pageNumber: widget.pageIndex + 1,
                isGame: isGame,
                onOpenGrid: widget.onOpenGrid != null ? () => widget.onOpenGrid!(widget.index) : null,
                onToggleComments: widget.onToggleComment,
                onToggleText: widget.onToggleText,
              );
            },
          )
              : SocialToolbar(
            imageId: null,
            pageId: pageId,
            fanzineId: widget.fanzineId,
            pageNumber: widget.pageIndex + 1,
            isGame: false,
            onOpenGrid: widget.onOpenGrid != null ? () => widget.onOpenGrid!(widget.index) : null,
            onToggleComments: widget.onToggleComment,
            onToggleText: widget.onToggleText,
          ),
        ),

        // Drawers (Overlays or expansions)
        // Note: In a fixed-height GridView, expanding drawers might cause overflow issues
        // if they exceed the cell bounds. The legacy single view used GridView,
        // effectively clipping or requiring scrolling *within* the item if it was complex.
        // However, standard drawers usually push content.
        // If the legacy view worked, it likely overlayed or the content was small.
        // We render them here conditionally.
        if (widget.isTextOpen)
          _buildTextDrawer(pageText, context),
        if (widget.isCommentsOpen)
          _buildCommentDrawer(widget.pageIndex, pageId ?? 'unknown'),
      ],
    );
  }

  Widget _buildTextDrawer(String text, BuildContext context) {
    if (text.isEmpty) {
      return Container(
          padding: const EdgeInsets.all(20),
          color: Colors.grey[100],
          alignment: Alignment.center,
          child: const Text("No transcription available.", style: TextStyle(color: Colors.grey)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      decoration: BoxDecoration(
          color: const Color(0xFFFDFBF7),
          border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: SelectableText.rich(LinkParser.renderLinks(context, text,
          baseStyle: const TextStyle(fontSize: 14, fontFamily: 'Georgia'))),
    );
  }

  Widget _buildCommentDrawer(int pageIndex, String pageId) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 100,
            child: StreamBuilder<QuerySnapshot>(
              stream: widget.engagementService.getCommentsStream(widget.fanzineId, pageId),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox();
                final docs = snap.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return Text("${data['username']}: ${data['text']}", style: const TextStyle(fontSize: 12));
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.commentController,
                  decoration: const InputDecoration(
                      hintText: "Comment...",
                      isDense: true,
                      border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => widget.onSubmitComment(pageIndex, pageId)),
            ],
          ),
        ],
      ),
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
  // Directly expose the URL state
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    // IMPORTANT: If imageUrl is provided, USE IT IMMEDIATELY.
    // This prevents the "loading after click" delay.
    _currentUrl = widget.imageUrl;

    // Only resolve storage path if we have absolutely nothing
    if ((_currentUrl == null || _currentUrl!.isEmpty) && widget.storagePath != null) {
      _resolveUrl();
    }
  }

  Future<void> _resolveUrl() async {
    if (widget.storagePath != null) {
      try {
        final url = await FirebaseStorage.instance.ref(widget.storagePath).getDownloadURL();
        if (mounted) setState(() => _currentUrl = url);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUrl == null || _currentUrl!.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // Standard Image.network uses internal cache.
    // Since we are now using GridView with cacheExtent + KeepAlive,
    // this widget stays mounted and the image stays painted.
    return Image.network(
      _currentUrl!,
      fit: BoxFit.contain,
      errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }
}