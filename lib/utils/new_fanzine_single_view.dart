import 'package:flutter/material.dart';
import '../services/view_service.dart';
import '../components/social_toolbar.dart';
import 'link_parser.dart';

class NewFanzineSingleView extends StatefulWidget {
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ViewService viewService;

  const NewFanzineSingleView({
    super.key,
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

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: widget.pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 30.0),
            child: widget.headerWidget,
          );
        }
        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        return Padding(
          padding: const EdgeInsets.only(bottom: 40.0),
          child: _buildPageItem(pageIndex, pageData),
        );
      },
    );
  }

  Widget _buildPageItem(int pageIndex, Map<String, dynamic> pageData) {
    final imageUrl = pageData['imageUrl'] ?? '';
    final imageId = pageData['imageId'];
    final String pageText = pageData['text_processed'] ?? pageData['text'] ?? '';
    final bool isTextOpen = _openTextDrawers[pageIndex] ?? false;
    final bool isCommentsOpen = _openCommentDrawers[pageIndex] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 0.65,
          child: Container(
            color: imageUrl.isEmpty ? Colors.grey[300] : Colors.white,
            child: imageUrl.isNotEmpty
                ? Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (c, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
            )
                : const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          ),
        ),
        Container(
          color: Colors.white,
          child: SocialToolbar(
            imageId: imageId,
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
          child: isCommentsOpen ? _buildCommentDrawer() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildTextDrawer(String text) {
    if (text.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        color: Colors.grey[100],
        alignment: Alignment.center,
        child: const Text("No transcription available.", style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7), // Warm paper-white
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TRANSCRIPTION",
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.5
            ),
          ),
          const SizedBox(height: 16),
          // Use our upgraded LinkParser
          SelectableText.rich(
            LinkParser.renderLinks(
              context,
              text,
              baseStyle: const TextStyle(
                fontSize: 16,
                height: 1.6, // Better readability line height
                color: Colors.black87,
                fontFamily: 'Georgia',
              ),
              linkStyle: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Colors.indigo,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: Colors.indigo.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentDrawer() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          const Text("Comments coming soon.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              hintText: "Write a letter of comment...",
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          )
        ],
      ),
    );
  }
}