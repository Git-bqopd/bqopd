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
  final Set<String> likedImageIds; // Pass downs down

  const FanzineListRenderer({
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    this.onOpenGrid,
    this.activeGlobalPanel,
    this.onTogglePanel,
    this.initialIndex = 0,
    this.preloadedImageStats = const {},
    required this.likedImageIds,
    super.key,
  });

  @override
  State<FanzineListRenderer> createState() => _FanzineListRendererState();
}

class _FanzineListRendererState extends State<FanzineListRenderer> {
  @override
  void initState() {
    super.initState();
    if (component.initialIndex > 0 && kIsWeb) {
      _anchorScroll();
    }
  }

  @override
  void didUpdateComponent(FanzineListRenderer oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialIndex != component.initialIndex && kIsWeb) {
      _anchorScroll();
    }
  }

  void _anchorScroll() {
    Future.microtask(() {
      final String targetId = component.initialIndex == 0
          ? 'fanzine-header'
          : 'reader-page-${component.initialIndex - 1}';

      scrollToElement(targetId);
    });
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'flex-col items-center w-full', [
      div(
          id: 'fanzine-header',
          classes: 'mb-4 flex justify-center w-full',
          [
            div(classes: 'manila-envelope', [component.headerWidget])
          ]
      ),

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
                likedImageIds: component.likedImageIds, // Pass downs down
                initialImageStats: component.preloadedImageStats[component.pages[i]['imageId']],
              )
            ]
        )
    ]);
  }
}