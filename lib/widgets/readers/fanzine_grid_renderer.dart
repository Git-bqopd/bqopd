import 'package:flutter/material.dart';
import '../../services/view_service.dart';

class FanzineGridRenderer extends StatelessWidget {
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

  void _recordViewForIndex(int index) {
    if (index > 0 && index <= pages.length) {
      final pageData = pages[index - 1];
      final imageId = pageData['imageId'];
      if (imageId != null) {
        viewService.recordView(contentId: imageId, contentType: 'images');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Standardizing the aspect ratio to 5:8 (0.625)
    const double childAspectRatio = 0.625;
    const double mainAxisSpacing = 30.0;
    const double crossAxisSpacing = 24.0;
    const double padding = 8.0;

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(padding),
      // We use SliverGridDelegateWithFixedCrossAxisCount which responds
      // automatically to the width of the parent container.
      // This makes it safe for responsive column resizing.
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      ),
      // +1 for the Header at index 0
      itemCount: pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // HEADER CELL
          return GestureDetector(
            onTap: () {
              // Optional: trigger something on cover tap
            },
            child: headerWidget,
          );
        }

        final pageIndex = index - 1;
        final pageData = pages[pageIndex];
        final imageUrl = pageData['imageUrl'] ?? '';
        final pageNum = pageData['pageNumber'] ?? (pageIndex + 1);

        return GestureDetector(
          onTap: () {
            _recordViewForIndex(index);
            onPageTap(index);
          },
          child: Container(
            decoration: BoxDecoration(
              color: imageUrl.isEmpty ? Colors.grey[300] : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: imageUrl.isNotEmpty
                ? Image.network(
              imageUrl,
              fit: BoxFit.contain, // Maintain aspect ratio within cell
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