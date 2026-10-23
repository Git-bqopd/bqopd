import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_utils.dart';
import 'fanzine_list_sticky_header.dart';
import 'reader_page_item.dart';

/// Vertically scrolling list renderer displaying each page in reading sequence
/// alongside the header envelope card.
/// Mounts the persistent 50px [FanzineListStickyHeader] at the top of Column 2's
/// scroll hierarchy so all publication pages glide underneath it when scrolled.
class FanzineListRenderer extends StatefulComponent {
  final String fanzineId;
  final String? shortCode;
  final String? fanzineType;
  final String? fanzineTitle;
  final bool isColumn1Open;
  final Component? stickyHeaderWidget;
  final List<Map<String, dynamic>> pages;
  final Component headerWidget;
  final VoidCallback? onOpenGrid;
  final BonusRowType? activeGlobalPanel;
  final void Function(BonusRowType type, int pageIndex)? onTogglePanel;
  final void Function(int pageIndex)? onPageImageTap;
  final int initialIndex;
  final Map<String, Map<String, dynamic>> preloadedImageStats;
  final Set<String> likedImageIds;
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool isEditingMode;
  final ToolScope? activeScope;

  const FanzineListRenderer({
    required this.fanzineId,
    this.shortCode,
    this.fanzineType,
    this.fanzineTitle,
    this.isColumn1Open = false,
    this.stickyHeaderWidget,
    required this.pages,
    required this.headerWidget,
    this.onOpenGrid,
    this.activeGlobalPanel,
    this.onTogglePanel,
    this.onPageImageTap,
    this.initialIndex = 0,
    this.preloadedImageStats = const {},
    required this.likedImageIds,
    this.authState,
    this.authBloc,
    this.isEditingMode = false,
    this.activeScope,
    super.key,
  });

  @override
  State<FanzineListRenderer> createState() => _FanzineListRendererState();
}

class _FanzineListRendererState extends State<FanzineListRenderer> {
  @override
  void initState() {
    super.initState();
    // Only anchor scroll on initial component mount if an initial target was requested
    if (component.initialIndex > 0 && kIsWeb) {
      _anchorInitialScroll();
    }
  }

  void _anchorInitialScroll() {
    Future.microtask(() {
      final String targetId = component.initialIndex == 0
          ? 'fanzine-header'
          : 'reader-page-${component.initialIndex - 1}';
      scrollToElement(targetId, block: 'center', smooth: false);
    });
  }

  @override
  Component build(BuildContext context) {
    Component? stickyHeader = component.stickyHeaderWidget;
    if (stickyHeader == null && !component.isEditingMode) {
      stickyHeader = FanzineListStickyHeader(
        title: component.fanzineTitle ?? '',
        shortCode: component.shortCode,
        isColumn1Open: component.isColumn1Open,
        authState: component.authState,
        authBloc: component.authBloc,
      );
    }

    return div(
      classes: 'flex-col items-center w-full',
      attributes: const {'style': 'position: relative; width: 100%;'},
      [
        if (stickyHeader != null) stickyHeader,
        div(
          id: 'fanzine-header',
          classes: 'fanzine-header-container mb-6 flex-row justify-center w-full',
          [
            div(
              classes:
              '${component.isEditingMode ? 'manila-envelope-flexible' : 'manila-envelope'} fanzine-header-wrapper',
              [component.headerWidget],
            )
          ],
        ),
        for (int i = 0; i < component.pages.length; i++)
          div(
            id: 'reader-page-$i',
            classes:
            'fanzine-page-container w-full flex-row justify-center mb-6',
            attributes: i == component.pages.length - 1
                ? const {
              'style':
              'padding-bottom: 24px; box-sizing: border-box; width: 100%;'
            }
                : const {
              'style': 'box-sizing: border-box; width: 100%;'
            },
            [
              div(
                classes: 'fanzine-page-wrapper w-full',
                attributes:
                const {'style': 'width: 100%; box-sizing: border-box;'},
                [
                  ReaderPageItem(
                    fanzineId: component.fanzineId,
                    shortCode: component.shortCode,
                    fanzineType: component.fanzineType,
                    pageData: component.pages[i],
                    pageIndex: i,
                    onOpenGrid: component.onOpenGrid,
                    activeGlobalPanel: component.activeGlobalPanel,
                    onTogglePanel: component.onTogglePanel,
                    onPageImageTap: component.onPageImageTap,
                    likedImageIds: component.likedImageIds,
                    initialImageStats: component
                        .preloadedImageStats[component.pages[i]['imageId']],
                    authState: component.authState,
                    authBloc: component.authBloc,
                    isEditingMode: component.isEditingMode,
                    activeScope: component.activeScope,
                  )
                ],
              )
            ],
          )
      ],
    );
  }
}