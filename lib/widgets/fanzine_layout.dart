import 'package:flutter/material.dart';
import '../services/view_service.dart';
import 'readers/fanzine_grid_renderer.dart';
import 'readers/fanzine_list_renderer.dart';

enum FanzineViewMode { grid, single }

class FanzineLayout extends StatelessWidget {
  final FanzineViewMode viewMode;
  final List<Map<String, dynamic>> pages;
  final String fanzineId;
  final Widget headerWidget;
  final ScrollController scrollController;
  final ViewService viewService;

  // Callbacks for mode switching
  final Function(int pageIndex) onSwitchToSingle;
  final Function(int pageIndex)? onSwitchToGrid; // Nullable if grid is disabled

  const FanzineLayout({
    super.key,
    required this.viewMode,
    required this.pages,
    required this.fanzineId,
    required this.headerWidget,
    required this.scrollController,
    required this.viewService,
    required this.onSwitchToSingle,
    this.onSwitchToGrid,
  });

  @override
  Widget build(BuildContext context) {
    if (viewMode == FanzineViewMode.grid) {
      return FanzineGridRenderer(
        pages: pages,
        headerWidget: headerWidget,
        scrollController: scrollController,
        viewService: viewService,
        onPageTap: (index) {
          // Grid index 0 is header, so pages start at 1
          onSwitchToSingle(index);
        },
      );
    } else {
      return FanzineListRenderer(
        fanzineId: fanzineId,
        pages: pages,
        headerWidget: headerWidget,
        scrollController: scrollController,
        viewService: viewService,
        onOpenGrid: onSwitchToGrid,
      );
    }
  }
}