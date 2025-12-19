import 'package:flutter/material.dart';
import '../services/view_service.dart';
import '../components/social_toolbar.dart'; // Updated import

class FanzineSingleView extends StatefulWidget {
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ScrollController scrollController;
  final Function(int) onOpenGrid;
  final ViewService viewService;

  const FanzineSingleView({
    super.key,
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
  // Local state for expandable boxes (Comment / Text inputs)
  // The SocialToolbar handles the "Drawer" state internally now.
  bool _areCommentBoxesOpen = false;
  bool _areTextBoxesOpen = false;

  void _toggleAllCommentBoxes() {
    setState(() {
      _areCommentBoxesOpen = !_areCommentBoxesOpen;
      if (_areCommentBoxesOpen) {
        _areTextBoxesOpen = false;
      }
    });
  }

  void _toggleAllTextBoxes() {
    setState(() {
      _areTextBoxesOpen = !_areTextBoxesOpen;
      if (_areTextBoxesOpen) {
        _areCommentBoxesOpen = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1 Column Grid Layout
    const int crossAxisCount = 1;
    const double childAspectRatio = 0.6;
    const double mainAxisSpacing = 30.0;
    const double crossAxisSpacing = 0.0;
    const double padding = 8.0;

    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(padding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      ),
      itemCount: widget.pages.length + 1, // +1 for Header
      itemBuilder: (context, index) {
        if (index == 0) {
          return widget.headerWidget;
        }

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        return _buildSingleColumnItem(index, pageData);
      },
    );
  }

  Widget _buildSingleColumnItem(int index, Map<String, dynamic> pageData) {
    final imageUrl = pageData['imageUrl'] ?? '';
    final imageId = pageData['imageId'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Image
        Expanded(
          child: Container(
            color: imageUrl.isEmpty ? Colors.grey[300] : null,
            child: imageUrl.isNotEmpty
                ? Image.network(imageUrl, fit: BoxFit.contain)
                : null,
          ),
        ),

        // 2. New Unified Social Toolbar
        SocialToolbar(
          imageId: imageId,
          onOpenGrid: () => widget.onOpenGrid(index),
          onToggleComments: _toggleAllCommentBoxes,
          onToggleText: _toggleAllTextBoxes,
        ),

        // 3. Expandable Boxes (External content areas triggered by the row)
        if (_areCommentBoxesOpen)
          _buildExpandableBox(title: 'Write a comment:', child: const Text("Comment input...")),
        if (_areTextBoxesOpen)
          _buildExpandableBox(title: 'Text:', child: const Text("Page text...")),
      ],
    );
  }

  Widget _buildExpandableBox({String? title, required Widget child}) {
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
            child,
          ],
        ),
      ),
    );
  }
}