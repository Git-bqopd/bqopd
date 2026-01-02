import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/view_service.dart';
import '../services/engagement_service.dart';
import '../components/social_toolbar.dart';
import 'link_parser.dart';

class FanzineSingleView extends StatefulWidget {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ScrollController scrollController;
  final Function(int) onOpenGrid;
  final ViewService viewService;

  const FanzineSingleView({
    super.key,
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    required this.scrollController,
    required this.onOpenGrid,
    required this.viewService,
  });

  @override
  State<FanzineSingleView> createState() => _FanzineSingleViewState();
}

class _FanzineSingleViewState extends State<FanzineSingleView> {
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        childAspectRatio: 0.6,
        mainAxisSpacing: 30.0,
      ),
      itemCount: widget.pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return widget.headerWidget;

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        return _buildSingleColumnItem(index, pageIndex, pageData);
      },
    );
  }

  Widget _buildSingleColumnItem(
      int index, int pageIndex, Map<String, dynamic> pageData) {
    final imageUrl = pageData['imageUrl'] ?? '';
    final imageId = pageData['imageId'] as String?;
    final pageId = pageData['__id'] ?? '';
    final String pageText =
        pageData['text_processed'] ?? pageData['text'] ?? '';

    final bool isTextOpen = _openTextDrawers[pageIndex] ?? false;
    final bool isCommentsOpen = _openCommentDrawers[pageIndex] ?? false;

    // Use a FutureBuilder to check the master Image document for "isGame"
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: imageUrl.isEmpty ? Colors.grey[300] : null,
            child: imageUrl.isNotEmpty
                ? Image.network(imageUrl, fit: BoxFit.contain)
                : null,
          ),
        ),
        if (imageId != null)
          FutureBuilder<DocumentSnapshot>(
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
                pageNumber: pageIndex + 1,
                isGame: isGame, // Passed logic
                onOpenGrid: () => widget.onOpenGrid(index),
                onToggleComments: () => _toggleCommentDrawer(pageIndex),
                onToggleText: () => _toggleTextDrawer(pageIndex),
              );
            },
          )
        else
          SocialToolbar(
            imageId: null,
            pageId: pageId,
            fanzineId: widget.fanzineId,
            pageNumber: pageIndex + 1,
            isGame: false,
            onOpenGrid: () => widget.onOpenGrid(index),
            onToggleComments: () => _toggleCommentDrawer(pageIndex),
            onToggleText: () => _toggleTextDrawer(pageIndex),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child:
          isTextOpen ? _buildTextDrawer(pageText) : const SizedBox.shrink(),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: isCommentsOpen
              ? _buildCommentDrawer(pageIndex, pageId)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildTextDrawer(String text) {
    if (text.isEmpty) {
      return Container(
          padding: const EdgeInsets.all(20),
          color: Colors.grey.shade500.withOpacity(0.1),
          alignment: Alignment.center,
          child: const Text("No transcription available."));
    }
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
          color: const Color(0xFFFDFBF7),
          border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: SelectableText.rich(
        LinkParser.renderLinks(context, text,
            baseStyle: const TextStyle(
                fontSize: 15, height: 1.5, fontFamily: 'Georgia')),
      ),
    );
  }

  Widget _buildCommentDrawer(int pageIndex, String pageId) {
    _commentControllers.putIfAbsent(pageIndex, () => TextEditingController());
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 100,
            child: StreamBuilder<QuerySnapshot>(
              stream:
              _engagementService.getCommentsStream(widget.fanzineId, pageId),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox();
                final docs = snap.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return Text("${data['username']}: ${data['text']}",
                        style: const TextStyle(fontSize: 12));
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
                  controller: _commentControllers[pageIndex],
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
}