import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/view_service.dart';
import '../services/engagement_service.dart';
import '../components/social_toolbar.dart';
import 'link_parser.dart';

class NewFanzineSingleView extends StatefulWidget {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ViewService viewService;

  const NewFanzineSingleView({
    super.key,
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    required this.viewService,
  });

  @override
  State<NewFanzineSingleView> createState() => _NewFanzineSingleViewState();
}

class _NewFanzineSingleViewState extends State<NewFanzineSingleView> {
  final Map<int, bool> _openTextDrawers = {};
  final Map<int, bool> _openCommentDrawers = {};
  final EngagementService _engagementService = EngagementService();
  final Map<int, TextEditingController> _commentControllers = {};

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error posting comment: $e')));
      }
    }
  }

  @override
  void dispose() {
    for (var c in _commentControllers.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: widget.pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(padding: const EdgeInsets.only(bottom: 30.0), child: widget.headerWidget);
        }
        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        return Padding(padding: const EdgeInsets.only(bottom: 40.0), child: _buildPageItem(pageIndex, pageData));
      },
    );
  }

  Widget _buildPageItem(int pageIndex, Map<String, dynamic> pageData) {
    final imageUrl = pageData['imageUrl'] as String?;
    final storagePath = pageData['storagePath'] as String?;
    final imageId = pageData['imageId'];
    final pageId = pageData['__id'];
    final String pageText = pageData['text_processed'] ?? pageData['text'] ?? '';
    final bool isTextOpen = _openTextDrawers[pageIndex] ?? false;
    final bool isCommentsOpen = _openCommentDrawers[pageIndex] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 0.65,
          child: Container(color: Colors.grey[100], child: _PageImage(imageUrl: imageUrl, storagePath: storagePath)),
        ),
        Container(
          color: Colors.white,
          child: SocialToolbar(
            imageId: imageId,
            pageId: pageId,
            fanzineId: widget.fanzineId,
            pageNumber: pageIndex + 1,
            onOpenGrid: null,
            onToggleComments: () => _toggleCommentDrawer(pageIndex),
            onToggleText: () => _toggleTextDrawer(pageIndex),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: isTextOpen ? _buildTextDrawer(pageText) : const SizedBox.shrink(),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: isCommentsOpen ? _buildCommentDrawer(pageIndex, pageId) : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildTextDrawer(String text) {
    if (text.isEmpty) return Container(padding: const EdgeInsets.all(20), color: Colors.grey[100], alignment: Alignment.center, child: const Text("No transcription available.", style: TextStyle(color: Colors.grey)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      decoration: BoxDecoration(color: const Color(0xFFFDFBF7), border: Border(top: BorderSide(color: Colors.grey.shade300), bottom: BorderSide(color: Colors.grey.shade300))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("TRANSCRIPTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
        const SizedBox(height: 16),
        SelectableText.rich(LinkParser.renderLinks(context, text, baseStyle: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87, fontFamily: 'Georgia'), linkStyle: TextStyle(fontSize: 16, height: 1.6, color: Colors.indigo, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: Colors.indigo.withOpacity(0.3)))),
      ]),
    );
  }

  Widget _buildCommentDrawer(int pageIndex, String pageId) {
    _commentControllers.putIfAbsent(pageIndex, () => TextEditingController());

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("LETTERS OF COMMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
          const SizedBox(height: 12),

          // Comments List
          SizedBox(
            height: 150,
            child: StreamBuilder<QuerySnapshot>(
              stream: _engagementService.getCommentsStream(widget.fanzineId, pageId),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text("No comments yet.", style: TextStyle(color: Colors.grey, fontSize: 12)));

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['username'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          Text(data['text'] ?? '', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(),
          const SizedBox(height: 8),

          // Input Area
          TextField(
            controller: _commentControllers[pageIndex],
            maxLines: 2,
            decoration: InputDecoration(
              hintText: "Write a letter of comment...",
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () => _submitComment(pageIndex, pageId),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
              child: const Text("Save", style: TextStyle(fontSize: 12)),
            ),
          )
        ],
      ),
    );
  }
}

class _PageImage extends StatefulWidget {
  final String? imageUrl; final String? storagePath;
  const _PageImage({this.imageUrl, this.storagePath});
  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  Future<String?>? _urlFuture;
  @override
  void initState() { super.initState(); _urlFuture = _resolveUrl(); }
  Future<String?> _resolveUrl() async {
    if (widget.storagePath != null && widget.storagePath!.isNotEmpty) {
      try { return await FirebaseStorage.instance.ref(widget.storagePath).getDownloadURL(); } catch (e) {}
    }
    return widget.imageUrl;
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final url = snapshot.data;
        if (url == null || url.isEmpty) return const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 48));
        return Image.network(url, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 48)));
      },
    );
  }
}