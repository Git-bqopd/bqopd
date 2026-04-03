import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  @override
  Widget build(BuildContext context) {
    const double childAspectRatio = 0.625;
    const double mainAxisSpacing = 30.0;
    const double crossAxisSpacing = 24.0;
    const double padding = 8.0;

    // Check if folio begins with a two-page spread
    // We also treat template pages (like the calendar) as spreads by default
    final bool startsWithSpread = widget.pages.isNotEmpty &&
        (widget.pages[0]['isSpread'] == true || widget.pages[0]['templateId'] != null);

    // If starts with spread, we add a placeholder at index 1 (between header and first page)
    final int extraTiles = startsWithSpread ? 1 : 0;

    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(padding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      ),
      itemCount: widget.pages.length + 1 + extraTiles,
      itemBuilder: (context, index) {
        // 0. Header Widget
        if (index == 0) return widget.headerWidget;

        // 1. Optional Placeholder for Spreads
        if (startsWithSpread && index == 1) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black12, width: 0.5),
            ),
            child: const Center(
              child: Text(
                "Cover Position\n(Spread Start)",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic),
              ),
            ),
          );
        }

        // 2. Normal Pages
        final pageIndex = index - 1 - extraTiles;
        final pageData = widget.pages[pageIndex];

        return _GridTile(
          index: index,
          pageData: pageData,
          onTap: () => widget.onPageTap(index),
          viewService: widget.viewService,
        );
      },
    );
  }
}

class _GridTile extends StatefulWidget {
  final int index;
  final Map<String, dynamic> pageData;
  final VoidCallback onTap;
  final ViewService viewService;

  const _GridTile({
    required this.index,
    required this.pageData,
    required this.onTap,
    required this.viewService,
  });

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
  String? _resolvedImageUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _recordView();
    _resolveUrl();
  }

  Future<void> _resolveUrl() async {
    final storagePath = widget.pageData['storagePath'];
    final imageUrl = widget.pageData['imageUrl'];

    if (storagePath != null && storagePath.toString().isNotEmpty) {
      try {
        final url = await FirebaseStorage.instance.ref(storagePath).getDownloadURL();
        if (mounted) setState(() { _resolvedImageUrl = url; _isLoading = false; });
        return;
      } catch (_) {}
    }

    if (mounted) setState(() { _resolvedImageUrl = imageUrl; _isLoading = false; });
  }

  void _recordView() {
    final String imageId = widget.pageData['imageId'] ?? '';
    final String pageId = widget.pageData['__id'] ?? '';

    if (imageId.isNotEmpty) {
      widget.viewService.recordView(
        imageId: imageId,
        pageId: pageId,
        fanzineId: 'grid_view',
        fanzineTitle: 'Gallery View',
        type: ViewType.grid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageNum = widget.pageData['pageNumber'] ?? widget.index;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty)
            ? Image.network(
          _resolvedImageUrl!,
          fit: BoxFit.contain,
          errorBuilder: (c, e, s) => Center(
            child: Text("Page $pageNum",
                style: const TextStyle(color: Colors.grey)),
          ),
        )
            : Center(child: Text("Page $pageNum")),
      ),
    );
  }
}