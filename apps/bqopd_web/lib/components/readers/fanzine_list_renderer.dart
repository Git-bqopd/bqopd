import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_utils.dart';
import 'reader_page_item.dart';

class FanzineListRenderer extends StatefulComponent {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Component headerWidget;
  final VoidCallback? onOpenGrid;
  final BonusRowType? activeGlobalPanel;
  final ValueChanged<BonusRowType>? onTogglePanel;
  final int initialIndex;
  final Map<String, Map<String, dynamic>> preloadedImageStats;

  const FanzineListRenderer({
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    this.onOpenGrid,
    this.activeGlobalPanel,
    this.onTogglePanel,
    this.initialIndex = 0,
    this.preloadedImageStats = const {},
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
    if (component.initialIndex > 0 && kIsWeb) {
      _anchorScroll();
    }
  }

  @override
  void didUpdateComponent(FanzineListRenderer oldComponent) {
    super.didUpdateComponent(oldComponent);
    // If the user clicks a different page in the grid or the URL updates, re-anchor
    if (oldComponent.initialIndex != component.initialIndex && kIsWeb) {
      _anchorScroll();
    }
  }

  void _anchorScroll() {
    // microtask ensures the DOM nodes from the 'for' loop are mounted before we query them
    Future.microtask(() {
      final String targetId = component.initialIndex == 0
          ? 'fanzine-header'
          : 'reader-page-${component.initialIndex - 1}';

      // Call the conditional utility instead of package:web directly
      scrollToElement(targetId);
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
                initialImageStats: component.preloadedImageStats[component.pages[i]['imageId']], // Supplies the cached stats block for individual pages
              )
            ]
        )
    ]);
  }
}