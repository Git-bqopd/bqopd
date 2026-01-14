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

  // NEW: Callback for desktop mode to show drawer externally
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
  final Map<int, bool> _openTextDrawers = {};
  final Map<int, bool> _openCommentDrawers = {};
  final EngagementService _engagementService = EngagementService();
  final Map<int, TextEditingController> _commentControllers = {};

  @override
  void dispose() {
    for (var c in _commentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _handleTextToggle(int index, String text) {
    if (widget.onExternalDrawerRequest != null) {
      // Desktop Mode: Send content to parent
      // Note: We don't toggle local state
      widget.onExternalDrawerRequest!(_buildTextDrawerContent(text));
    } else {
      // Mobile Mode: Toggle local state
      setState(() {
        final isOpen = _openTextDrawers[index] ?? false;
        _openTextDrawers[index] = !isOpen;
        if (_openTextDrawers[index] == true) _openCommentDrawers[index] = false;
      });
    }
  }

  void _handleCommentToggle(int index, String pageId) {
    if (widget.onExternalDrawerRequest != null) {
      // Desktop Mode
      widget.onExternalDrawerRequest!(_buildCommentDrawerContent(index, pageId));
    } else {
      // Mobile Mode
      setState(() {
        final isOpen = _openCommentDrawers[index] ?? false;
        _openCommentDrawers[index] = !isOpen;
        if (_openCommentDrawers[index] == true) _openTextDrawers[index] = false;
      });
    }
  }

  // --- DRAWER CONTENT BUILDERS (Shared) ---

  Widget _buildTextDrawerContent(String text) {
    // Wrapped in a container for the external view consistency
    return Container(
      color: const Color(0xFFFDFBF7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: const Text("TRANSCRIPTION", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: text.isEmpty
                  ? const Center(child: Text("No transcription available.", style: TextStyle(color: Colors.grey)))
                  : SelectableText.rich(LinkParser.renderLinks(context, text,
                  baseStyle: const TextStyle(fontSize: 14, fontFamily: 'Georgia'))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentDrawerContent(int pageIndex, String pageId) {
    // Ensure controller exists
    final controller = _commentControllers.putIfAbsent(pageIndex, () => TextEditingController());

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: const Text("COMMENTS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _engagementService.getCommentsStream(widget.fanzineId, pageId),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text("No comments yet."));

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (c,i) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return ListTile(
                      dense: true,
                      title: Text(data['username'] ?? 'Anon', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(data['text'] ?? ''),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300))
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                        hintText: "Add a comment...",
                        isDense: true,
                        border: OutlineInputBorder()),
                    onSubmitted: (_) => _submitComment(pageIndex, pageId),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _submitComment(pageIndex, pageId)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- LOCAL DRAWER BUILDERS (For Mobile Inline) ---
  // These wrap the content in a constrained box or style appropriate for inline display

  Widget _buildInlineTextDrawer(String text) {
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

  Widget _buildInlineCommentDrawer(int pageIndex, String pageId) {
    final controller = _commentControllers.putIfAbsent(pageIndex, () => TextEditingController());
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200, // Fixed height for inline
            child: StreamBuilder<QuerySnapshot>(
              stream: _engagementService.getCommentsStream(widget.fanzineId, pageId),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox();
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text("No comments yet."));
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: RichText(text: TextSpan(style: const TextStyle(color: Colors.black), children: [
                        TextSpan(text: "${data['username']}: ", style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: "${data['text']}"),
                      ])),
                    );
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
                  controller: controller,
                  decoration: const InputDecoration(
                      hintText: "Comment...",
                      isDense: true,
                      border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _submitComment(pageIndex, pageId)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submitComment(int pageIndex, String pageId) async {
    final controller = _commentControllers[pageIndex];
    if (controller == null || controller.text.trim().isEmpty) return;

    final text = controller.text.trim();
    controller.clear();
    // Only unfocus if on mobile/inline to avoid jarring keyboard dismissal on desktop
    if (widget.onExternalDrawerRequest == null) {
      FocusScope.of(context).unfocus();
    }

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
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1, // Single Column
        childAspectRatio: 0.625, // 5:8 Ratio
        mainAxisSpacing: 30.0,
      ),
      cacheExtent: 5000.0,
      itemCount: widget.pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return widget.headerWidget;
        }

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        return _KeepAlivePageItem(
          index: index,
          pageIndex: pageIndex,
          pageData: pageData,
          fanzineId: widget.fanzineId,
          isTextOpen: _openTextDrawers[pageIndex] ?? false,
          isCommentsOpen: _openCommentDrawers[pageIndex] ?? false,
          onToggleText: () => _handleTextToggle(pageIndex, pageData['text_processed'] ?? pageData['text'] ?? ''),
          onToggleComment: () => _handleCommentToggle(pageIndex, pageData['__id']),
          onOpenGrid: widget.onOpenGrid,
          // We pass inline builders for the mobile logic
          inlineTextDrawerBuilder: _buildInlineTextDrawer,
          inlineCommentDrawerBuilder: _buildInlineCommentDrawer,
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
  final Widget Function(String) inlineTextDrawerBuilder;
  final Widget Function(int, String) inlineCommentDrawerBuilder;

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
    required this.inlineTextDrawerBuilder,
    required this.inlineCommentDrawerBuilder,
  });

  @override
  State<_KeepAlivePageItem> createState() => _KeepAlivePageItemState();
}

class _KeepAlivePageItemState extends State<_KeepAlivePageItem> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final imageUrl = widget.pageData['imageUrl'] as String?;
    final storagePath = widget.pageData['storagePath'] as String?;
    final imageId = widget.pageData['imageId'] as String?;
    final pageId = widget.pageData['__id'];
    final String pageText = widget.pageData['text_processed'] ?? widget.pageData['text'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: _PageImage(imageUrl: imageUrl, storagePath: storagePath),
          ),
        ),
        Container(
          color: Colors.white,
          child: FutureBuilder<DocumentSnapshot>(
            future: imageId != null
                ? FirebaseFirestore.instance.collection('images').doc(imageId).get()
                : null,
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
          ),
        ),
        // Drawers (Only visible if local state allows)
        if (widget.isTextOpen)
          widget.inlineTextDrawerBuilder(pageText),
        if (widget.isCommentsOpen)
          widget.inlineCommentDrawerBuilder(widget.pageIndex, pageId ?? 'unknown'),
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
    _currentUrl = widget.imageUrl;
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
    return Image.network(
      _currentUrl!,
      fit: BoxFit.contain,
      errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }
}