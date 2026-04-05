import 'package:flutter/material.dart';
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
  final String _fanzineTitle = 'Gallery View';
  final String _fanzineId = 'grid_view';

  @override
  Widget build(BuildContext context) {
    final int totalItems = widget.pages.length + 1;
    final int rowCount = (totalItems / 2).ceil();

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(vertical: 24),
      itemCount: rowCount,
      itemBuilder: (context, rowIndex) {
        final int leftItemIndex = rowIndex * 2;
        final int rightItemIndex = leftItemIndex + 1;

        Widget? leftWidget;
        Map<String, dynamic>? leftPageData;
        if (leftItemIndex == 0) {
          leftWidget = widget.headerWidget;
        } else {
          leftPageData = widget.pages[leftItemIndex - 1];
        }

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