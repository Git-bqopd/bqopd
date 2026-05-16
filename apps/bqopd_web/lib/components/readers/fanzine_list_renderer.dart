import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:web/web.dart' as web;
import 'package:bqopd_core/bqopd_core.dart';
import 'reader_page_item.dart';

class FanzineListRenderer extends StatefulComponent {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Component headerWidget;
  final VoidCallback? onOpenGrid;
  final BonusRowType? activeGlobalPanel;
  final ValueChanged<BonusRowType>? onTogglePanel;
  final int initialIndex;

  const FanzineListRenderer({
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    this.onOpenGrid,
    this.activeGlobalPanel,
    this.onTogglePanel,
    this.initialIndex = 0,
    super.key,
  });

  @override
  State<FanzineListRenderer> createState() => _FanzineListRendererState();
}

class _FanzineListRendererState extends State<FanzineListRenderer> {
  @override
  void initState() {
    super.initState();
    // Anchor scroll on initial load if we aren't starting at the very top
    if (component.initialIndex > 0) {
      _anchorScroll();
    }
  }

  @override
  void didUpdateComponent(FanzineListRenderer oldComponent) {
    super.didUpdateComponent(oldComponent);
    // If the user clicks a different page in the grid or the URL updates, re-anchor
    if (oldComponent.initialIndex != component.initialIndex) {
      _anchorScroll();
    }
  }

  void _anchorScroll() {
    // microtask ensures the DOM nodes from the 'for' loop are mounted before we query them
    Future.microtask(() {
      final String targetId = component.initialIndex == 0
          ? 'fanzine-header'
          : 'reader-page-${component.initialIndex - 1}';

      final el = web.document.getElementById(targetId);
      if (el != null) {
        // Use package:web types to trigger the browser's native scroll logic.
        // The block: 'start' aligns the top of the target page with the top of the reader column.
        el.scrollIntoView(web.ScrollIntoViewOptions(
          behavior: 'auto',
          block: 'start',
        ));
      }
    });
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'flex-col items-center w-full', [
      // 1. The Header Anchor (Index 0)
      div(
          id: 'fanzine-header',
          classes: 'mb-4 flex justify-center w-full',
          [
            div(classes: 'manila-envelope', [component.headerWidget])
          ]
      ),

      // 2. The Full Page List (Rendered completely to allow free scrolling)
      for (int i = 0; i < component.pages.length; i++)
        div(
            id: 'reader-page-$i',
            classes: 'w-full',
            [
              ReaderPageItem(
                fanzineId: component.fanzineId,
                pageData: component.pages[i],
                pageIndex: i,
                onOpenGrid: component.onOpenGrid,
              )
            ]
        )
    ]);
  }
}