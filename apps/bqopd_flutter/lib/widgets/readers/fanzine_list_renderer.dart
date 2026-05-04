import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'reader_page_item.dart';
import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_core/bqopd_core.dart';

class FanzineListRenderer extends StatefulWidget {
  final String fanzineId;
  final String? fanzineType;
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ItemScrollController itemScrollController;
  final ViewService viewService;

  final bool isEditingMode;
  final bool isDesktopLayout;

  final BonusRowType? activeGlobalPanel;
  final Function(BonusRowType) onTogglePanel;

  final VoidCallback? onOpenGrid;
  final int initialIndex;

  const FanzineListRenderer({
    super.key,
    required this.fanzineId,
    this.fanzineType,
    required this.pages,
    required this.headerWidget,
    required this.itemScrollController,
    required this.viewService,
    this.isEditingMode = false,
    this.isDesktopLayout = false,
    this.activeGlobalPanel,
    required this.onTogglePanel,
    this.onOpenGrid,
    this.initialIndex = 0,
  });

  @override
  State<FanzineListRenderer> createState() => _FanzineListRendererState();
}

class _FanzineListRendererState extends State<FanzineListRenderer> {
  String _fanzineTitle = '...';

  @override
  void initState() {
    super.initState();
    _fetchFanzineMeta();
  }

  Future<void> _fetchFanzineMeta() async {
    final doc = await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).get();
    if (doc.exists && mounted) {
      setState(() => _fanzineTitle = doc.data()?['title'] ?? 'Untitled');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScrollablePositionedList.separated(
      itemScrollController: widget.itemScrollController,
      initialScrollIndex: widget.initialIndex,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.pages.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 48),
      itemBuilder: (context, index) {
        if (index == 0) {
          return widget.headerWidget;
        }

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];

        return ReaderPageItem(
          fanzineId: widget.fanzineId,
          fanzineTitle: _fanzineTitle,
          fanzineType: widget.fanzineType,
          pageData: pageData,
          pageIndex: pageIndex,
          isEditingMode: widget.isEditingMode,
          isDesktopLayout: widget.isDesktopLayout,
          activeGlobalPanel: widget.activeGlobalPanel,
          onTogglePanel: widget.onTogglePanel,
          onOpenGrid: widget.onOpenGrid,
        );
      },
    );
  }
}