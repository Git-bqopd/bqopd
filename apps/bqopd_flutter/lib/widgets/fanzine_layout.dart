import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'readers/fanzine_grid_renderer.dart';
import 'readers/fanzine_list_renderer.dart';
import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_core/bqopd_core.dart';

enum FanzineViewMode { grid, single }

class FanzineLayout extends StatelessWidget {
  final FanzineViewMode viewMode;
  final List<Map<String, dynamic>> pages;
  final String fanzineId;
  final String? fanzineType;
  final Widget headerWidget;

  final ScrollController gridScrollController;
  final ItemScrollController listScrollController;
  final int initialIndex;

  final bool isEditingMode;

  final BonusRowType? activeGlobalPanel;
  final Function(BonusRowType) onTogglePanel;

  final ViewService viewService;
  final Function(int pageIndex) onSwitchToSingle;

  final VoidCallback? onOpenGrid;

  const FanzineLayout({
    super.key,
    required this.viewMode,
    required this.pages,
    required this.fanzineId,
    this.fanzineType,
    required this.headerWidget,
    required this.gridScrollController,
    required this.listScrollController,
    required this.initialIndex,
    required this.isEditingMode,
    this.activeGlobalPanel,
    required this.onTogglePanel,
    required this.viewService,
    required this.onSwitchToSingle,
    this.onOpenGrid,
  });

  @override
  Widget build(BuildContext context) {
    if (viewMode == FanzineViewMode.grid) {
      return FanzineGridRenderer(
        pages: pages,
        headerWidget: headerWidget,
        scrollController: gridScrollController,
        viewService: viewService,
        onPageTap: onSwitchToSingle,
      );
    } else {
      return FanzineListRenderer(
        fanzineId: fanzineId,
        fanzineType: fanzineType,
        pages: pages,
        headerWidget: headerWidget,
        itemScrollController: listScrollController,
        initialIndex: initialIndex,
        viewService: viewService,
        isEditingMode: isEditingMode,
        isDesktopLayout: false,
        activeGlobalPanel: activeGlobalPanel,
        onTogglePanel: onTogglePanel,
        onOpenGrid: onOpenGrid,
      );
    }
  }
}