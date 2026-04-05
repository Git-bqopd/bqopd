import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/view_service.dart';
import 'fanzine_spread_tile.dart';

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
  String _fanzineTitle = 'Gallery View';
  String _fanzineId = 'grid_view';

  @override
  void initState() {
    super.initState();
    // Attempt to resolve context if possible, though mostly for analytics tagging
    _findFanzineContext();
  }

  void _findFanzineContext() {
    if (widget.pages.isNotEmpty) {
      // Pages usually carry a fanzineId if they were fetched as a collection
      // But GridRenderer is often used for the generic gallery.
    }
  }

  @override
  Widget build(BuildContext context) {
    // We treat the sequence as: Header, Page0, Page1, Page2...
    // Total items = pages.length + 1
    // Total rows = ceil(total items / 2)
    final int totalItems = widget.pages.length + 1;
    final int rowCount = (totalItems / 2).ceil();

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(vertical: 24),
      itemCount: rowCount,
      itemBuilder: (context, rowIndex) {
        // Calculate item indices for this row
        final int leftItemIndex = rowIndex * 2;
        final int rightItemIndex = leftItemIndex + 1;

        // Determine left content
        Widget? leftWidget;
        Map<String, dynamic>? leftPageData;
        if (leftItemIndex == 0) {
          leftWidget = widget.headerWidget;
        } else {
          // Page index is item index - 1
          leftPageData = widget.pages[leftItemIndex - 1];
        }

        // Determine right content
        Map<String, dynamic>? rightPageData;
        if (rightItemIndex < totalItems) {
          rightPageData = widget.pages[rightItemIndex - 1];
        }

        return FanzineSpreadTile(
          leftWidget: leftWidget,
          leftPageData: leftPageData,
          rightPageData: rightPageData,
          leftIndex: leftItemIndex,
          rightIndex: rightItemIndex,
          onPageTap: widget.onPageTap,
          viewService: widget.viewService,
          fanzineId: _fanzineId,
          fanzineTitle: _fanzineTitle,
        );
      },
    );
  }
}