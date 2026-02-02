import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/view_service.dart';

class FanzineGridRenderer extends StatefulWidget {
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ScrollController scrollController;
  final Function(int) onPageTap;
  final ViewService viewService;

  const FanzineGridRenderer({
    super.key,
    required this.pages,
    required this.headerWidget,
    required this.scrollController,
    required this.onPageTap,
    required this.viewService,
  });

  @override
  State<FanzineGridRenderer> createState() => _FanzineGridRendererState();
}

class _FanzineGridRendererState extends State<FanzineGridRenderer> {
  void _recordGridView(int index) async {
    if (index == 0) return;
    final pageData = widget.pages[index - 1];
    final String imageId = pageData['imageId'] ?? '';
    final String pageId = pageData['__id'] ?? '';

    widget.viewService.recordView(
      imageId: imageId,
      pageId: pageId, // Fixed: Added required pageId argument
      fanzineId: 'grid_view',
      fanzineTitle: 'Gallery View',
      type: ViewType.grid,
    );
  }

  @override
  Widget build(BuildContext context) {
    const double childAspectRatio = 0.625;
    const double mainAxisSpacing = 30.0;
    const double crossAxisSpacing = 24.0;
    const double padding = 8.0;

    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(padding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      ),
      itemCount: widget.pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return widget.headerWidget;

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        final imageUrl = pageData['imageUrl'] ?? '';
        final pageNum = pageData['pageNumber'] ?? (pageIndex + 1);

        return GestureDetector(
          onTap: () {
            _recordGridView(index);
            widget.onPageTap(index);
          },
          child: Container(
            decoration: BoxDecoration(
              color: imageUrl.isEmpty ? Colors.grey[300] : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: imageUrl.isNotEmpty
                ? Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (c, e, s) => Center(
                child: Text("Page $pageNum",
                    style: const TextStyle(color: Colors.grey)),
              ),
            )
                : Center(child: Text("Page $pageNum")),
          ),
        );
      },
    );
  }
}