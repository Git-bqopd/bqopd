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
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool isEditingMode;

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
    this.authState,
    this.authBloc,
    this.isEditingMode = false,
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
    final String headerStyle = component.isEditingMode
        ? 'width: 600px; max-width: 100%; box-sizing: border-box;'
        : 'width: calc((100vh - 120px) * 0.625); max-width: 100%; box-sizing: border-box;';

    return div(classes: 'flex-col items-center w-full', [
      // Manila Envelope / Workspace Editor Widget: Spans 600px wide if editing, otherwise perfectly matches the outer boundaries of the padded images below.
      div(
          id: 'fanzine-header',
          classes: 'mb-4 flex-row justify-center w-full',
          [
            div(
                classes: component.isEditingMode ? 'manila-envelope-flexible' : 'manila-envelope',
                attributes: {
                  'style': headerStyle
                },
                [component.headerWidget]
            )
          ]
      ),

      // Page Images Loop: Centered inner column constrained to the height-based aspect ratio!
      for (int i = 0; i < component.pages.length; i++)
        div(
            id: 'reader-page-$i',
            classes: 'w-full flex-row justify-center', // Centers the inner column using flex-row
            attributes: i == component.pages.length - 1
                ? const {
              'style': 'padding-bottom: 48px; box-sizing: border-box;'
            }
                : const {
              'style': 'box-sizing: border-box;'
            },
            [
              // Inside column: Dynamically calculates the optimal width while safeguarding against overflow
              div(
                  attributes: const {
                    'style': 'width: calc((100vh - 120px) * 0.625); max-width: 100%; padding-left: 24px; padding-right: 24px; box-sizing: border-box;'
                  },
                  [
                    ReaderPageItem(
                      fanzineId: component.fanzineId, // Correctly resolved field getter
                      pageData: component.pages[i],
                      pageIndex: i,
                      onOpenGrid: component.onOpenGrid,
                      likedImageIds: component.likedImageIds, // Pass downs down
                      initialImageStats: component.preloadedImageStats[component.pages[i]['imageId']],
                      authState: component.authState,
                      authBloc: component.authBloc,
                      isEditingMode: component.isEditingMode,
                    )
                  ]
              )
            ]
        )
    ]);
  }
}