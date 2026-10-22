import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'fanzine_header.dart';
import 'fanzine_reader.dart';
import 'readers/fanzine_grid_renderer.dart';
import 'readers/fanzine_list_renderer.dart';
import 'readers/panel_column_renderer.dart';
import '../utils/web_utils.dart';
import 'package:bqopd_core/bqopd_core.dart';

enum FanzineViewMode { grid, single }

/// Multi-column responsive layout coordinator managing grid spreads,
/// vertical list views, and collapsible desktop bonus panels.
/// Enforces directional scroll relationships:
/// 1. Scrolling in Column 1 never changes Column 2 or Column 3.
/// 2. Scrolling in Column 2 keeps Column 1 centered vertically, but never touches Column 3.
/// 3. Scrolling in Column 3 auto-centers both Column 1 and Column 2 to their matching widgets.
class FanzineLayout extends StatefulComponent {
  final String frefFanzineId;
  final String? shortCode;
  final String? fanzineType;
  final String? fanzineTitle;
  final List<Map<String, dynamic>> pages;
  final Component gridHeader;
  final Component? gridStickyHeader;
  final Component listHeader;
  final Component? listStickyHeader;
  final bool hasCover;
  final bool twoPage;
  final int? initialPageNumber;
  final BonusRowType? initialPanel;
  final Map<String, Map<String, dynamic>> preloadedImageStats;
  final Set<String> likedImageIds;
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool isEditingMode;
  final ToolScope? activeScope;

  const FanzineLayout({
    required String fanzineId,
    this.shortCode,
    this.fanzineType,
    this.fanzineTitle,
    required this.pages,
    required this.gridHeader,
    this.gridStickyHeader,
    required this.listHeader,
    this.listStickyHeader,
    this.hasCover = true,
    this.twoPage = true,
    this.initialPageNumber,
    this.initialPanel,
    this.preloadedImageStats = const {},
    required this.likedImageIds,
    this.authState,
    this.authBloc,
    this.isEditingMode = false,
    this.activeScope,
    super.key,
  }) : frefFanzineId = fanzineId;

  @override
  State<FanzineLayout> createState() => _FanzineLayoutState();
}

class _FanzineLayoutState extends State<FanzineLayout> {
  FanzineViewMode _viewMode = FanzineViewMode.grid;

  int _listTargetIndex = 0;
  int _panelTargetIndex = 0;

  BonusRowType? _activeGlobalPanel;
  int? _lastFullyInFrameIndex;
  bool _isProgrammaticScrolling = false;
  Timer? _programmaticScrollTimer;
  int _activeScrollSource = 0; // 1: Col 1, 2: Col 2, 3: Col 3

  @override
  void initState() {
    super.initState();
    if (component.isEditingMode) {
      _viewMode = FanzineViewMode.single;
    }
    if (component.initialPageNumber != null && component.initialPageNumber! > 0) {
      _listTargetIndex = component.initialPageNumber!;
      _panelTargetIndex = component.initialPageNumber!;
      _viewMode = FanzineViewMode.single;
    }
    if (component.initialPanel != null) {
      _activeGlobalPanel = component.initialPanel;
    }
  }

  @override
  void didUpdateComponent(FanzineLayout oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.isEditingMode != component.isEditingMode) {
      setState(() {
        if (component.isEditingMode) {
          _viewMode = FanzineViewMode.single;
        } else {
          _viewMode = FanzineViewMode.grid;
        }
      });
    }
    if (oldComponent.initialPanel != component.initialPanel &&
        component.initialPanel != null) {
      setState(() {
        _activeGlobalPanel = component.initialPanel;
      });
    }
  }

  @override
  void dispose() {
    _programmaticScrollTimer?.cancel();
    super.dispose();
  }

  void _switchToSingle(int index) {
    _lastFullyInFrameIndex = index;
    final totalItems = component.pages.length + 1;

    _isProgrammaticScrolling = true;
    _activeScrollSource = 1;
    _programmaticScrollTimer?.cancel();
    _programmaticScrollTimer = Timer(const Duration(milliseconds: 650), () {
      _isProgrammaticScrolling = false;
      _activeScrollSource = 0;
    });

    Future.microtask(() {
      _syncColumn1(index, totalItems);
    });

    if (_activeGlobalPanel != null && index > 0) {
      Future.microtask(() {
        centerElementInContainer(
          'panel-column-scroll-area',
          'panel-page-${index - 1}',
          smooth: true,
        );
      });
    }

    final String targetId = index == 0
        ? 'fanzine-header'
        : 'reader-page-${index - 1}';
    scrollToElement(targetId, block: 'center', smooth: true);

    if (_viewMode != FanzineViewMode.single || _listTargetIndex != index) {
      setState(() {
        _listTargetIndex = index;
        _panelTargetIndex = index;
        _viewMode = FanzineViewMode.single;
      });
    }
  }

  void _switchToGrid() {
    setState(() {
      _viewMode = FanzineViewMode.grid;
    });
  }

  void _handleTogglePanel(BonusRowType type, int pageIndex) {
    final int listIndex = pageIndex + 1;
    final bool isSamePanelAndTarget =
    (_activeGlobalPanel == type && _panelTargetIndex == listIndex);

    if (isSamePanelAndTarget) {
      setState(() {
        _activeGlobalPanel = null;
      });
      return;
    }

    _lastFullyInFrameIndex = listIndex;
    final totalItems = component.pages.length + 1;

    _isProgrammaticScrolling = true;
    _activeScrollSource = 2;
    _programmaticScrollTimer?.cancel();
    _programmaticScrollTimer = Timer(const Duration(milliseconds: 650), () {
      _isProgrammaticScrolling = false;
      _activeScrollSource = 0;
    });

    setState(() {
      _activeGlobalPanel = type;
      _listTargetIndex = listIndex;
      _panelTargetIndex = listIndex;
    });

    Future.microtask(() {
      _syncColumn1(listIndex, totalItems);
    });

    final String targetId = 'reader-page-$pageIndex';
    scrollToElement(targetId, block: 'center', smooth: true);

    Future.microtask(() {
      scrollElementToTopOfContainer(
        'panel-column-scroll-area',
        'panel-page-$pageIndex',
        smooth: true,
        offset: 16.0,
      );
    });
  }

  void _cancelProgrammaticScroll() {
    if (_isProgrammaticScrolling) {
      _programmaticScrollTimer?.cancel();
      _isProgrammaticScrolling = false;
      _activeScrollSource = 0;
    }
  }

  void _handleListScroll() {
    if (!kIsWeb) return;

    final bool enableTwoPage = component.twoPage;
    final isGrid = enableTwoPage ? (_viewMode == FanzineViewMode.grid) : false;
    if (isGrid) return;

    if (_isProgrammaticScrolling && _activeScrollSource != 2) {
      return;
    }

    final totalItems = component.pages.length + 1;

    final activeIndex = calculateListScrollActiveIndex(
      containerId: 'fanzine-list-area',
      totalItems: totalItems,
      itemIdBuilder: (i) => i == 0 ? 'fanzine-header' : 'reader-page-${i - 1}',
    );

    if (activeIndex != null && activeIndex != _lastFullyInFrameIndex) {
      _lastFullyInFrameIndex = activeIndex;
      _listTargetIndex = activeIndex;
      _syncColumn1(activeIndex, totalItems);
    }
  }

  void _updateTargetFromColumn3(int pageIndex) {
    final listIndex = pageIndex + 1;
    if (_lastFullyInFrameIndex == listIndex && _activeScrollSource == 3) {
      return;
    }
    _lastFullyInFrameIndex = listIndex;

    setState(() {
      _listTargetIndex = listIndex;
      _panelTargetIndex = listIndex;
    });

    _isProgrammaticScrolling = true;
    _activeScrollSource = 3;
    _programmaticScrollTimer?.cancel();
    _programmaticScrollTimer = Timer(const Duration(milliseconds: 650), () {
      _isProgrammaticScrolling = false;
      _activeScrollSource = 0;
    });

    final String targetId = 'reader-page-$pageIndex';
    scrollToElement(targetId, block: 'center', smooth: true);

    final totalItems = component.pages.length + 1;
    _syncColumn1(listIndex, totalItems);
  }

  void _handlePanelCardTap(int pageIndex) {
    final listIndex = pageIndex + 1;
    _lastFullyInFrameIndex = listIndex;

    _isProgrammaticScrolling = true;
    _activeScrollSource = 3;
    _programmaticScrollTimer?.cancel();
    _programmaticScrollTimer = Timer(const Duration(milliseconds: 650), () {
      _isProgrammaticScrolling = false;
      _activeScrollSource = 0;
    });

    setState(() {
      _listTargetIndex = listIndex;
      _panelTargetIndex = listIndex;
    });

    centerElementInContainer(
      'panel-column-scroll-area',
      'panel-page-$pageIndex',
      smooth: true,
    );

    final String targetId = 'reader-page-$pageIndex';
    scrollToElement(targetId, block: 'center', smooth: true);

    final totalItems = component.pages.length + 1;
    _syncColumn1(listIndex, totalItems);
  }

  void _syncColumn1(int itemIndex, int totalItems) {
    final bool hasCover = component.hasCover;

    if (itemIndex == 0 || (hasCover && itemIndex == 1)) {
      scrollContainerToTop('fanzine-grid-area', smooth: true);
      return;
    }

    if (itemIndex == totalItems - 1) {
      scrollContainerToBottom('fanzine-grid-area', smooth: true);
      return;
    }

    final spreadIndex = getSpreadIndexForListIndex(
      listIndex: itemIndex,
      pages: component.pages,
      hasCover: hasCover,
    );
    centerElementInContainer(
      'fanzine-grid-area',
      'grid-spread-$spreadIndex',
      smooth: true,
    );
  }

  @override
  Component build(BuildContext context) {
    final bool enableTwoPage = component.twoPage;
    final bool isGrid = enableTwoPage ? (_viewMode == FanzineViewMode.grid) : false;
    final bool showThirdColumn = !isGrid && _activeGlobalPanel != null;
    final bool isColumn1Open = enableTwoPage && !isGrid;

    String? resolvedTitle = component.fanzineTitle;
    if (resolvedTitle == null && component.listHeader is FanzineReader) {
      final reader = component.listHeader as FanzineReader;
      final rawTitle = reader.fanzineData?['title'];
      if (rawTitle is String) {
        resolvedTitle = rawTitle;
      }
    }

    Component activeListHeader = component.listHeader;
    if (activeListHeader is FanzineReader) {
      activeListHeader = FanzineReader(
        fanzineId: activeListHeader.fanzineId,
        shortCode: activeListHeader.shortCode,
        fanzineData: activeListHeader.fanzineData,
        creatorProfiles: activeListHeader.creatorProfiles,
        imageStats: activeListHeader.imageStats,
        pageStructure: activeListHeader.pageStructure,
        authState: activeListHeader.authState,
        authBloc: activeListHeader.authBloc,
        isColumn1Open: isColumn1Open,
        showBottomBar: true,
        key: activeListHeader.key,
      );
    }

    Component activeGridHeader = component.gridHeader;
    if (!component.isEditingMode && isGrid) {
      if (component.listHeader is FanzineReader) {
        final reader = component.listHeader as FanzineReader;
        activeGridHeader = FanzineReader(
          fanzineId: reader.fanzineId,
          shortCode: reader.shortCode,
          fanzineData: reader.fanzineData,
          creatorProfiles: reader.creatorProfiles,
          imageStats: reader.imageStats,
          pageStructure: reader.pageStructure,
          authState: reader.authState,
          authBloc: reader.authBloc,
          isColumn1Open: false,
          showBottomBar: false,
          key: reader.key,
        );
      } else {
        activeGridHeader = component.listHeader;
      }
    }

    final String layoutClasses = isGrid
        ? 'reader-split-layout grid-only'
        : 'reader-split-layout has-list-area';

    final String gridClasses = isGrid
        ? 'grid-area'
        : 'grid-area hidden-on-mobile';

    final String listMode = component.isEditingMode ? 'editor-mode' : 'reader-mode';
    final String listClasses = 'list-area $listMode flex-col items-center';

    return div(
      classes: layoutClasses,
      [
        if (enableTwoPage)
          div(
            id: 'fanzine-grid-area',
            classes: gridClasses,
            attributes: {
              'style': isGrid ? 'flex: 1;' : 'flex: 0 0 450px;'
            },
            events: {
              'wheel': (e) {
                _cancelProgrammaticScroll();
                _activeScrollSource = 1;
              },
              'touchstart': (e) {
                _cancelProgrammaticScroll();
                _activeScrollSource = 1;
              },
              'pointerdown': (e) {
                _cancelProgrammaticScroll();
                _activeScrollSource = 1;
              },
            },
            [
              FanzineGridRenderer(
                pages: component.pages,
                headerWidget: activeGridHeader,
                stickyHeaderWidget: component.gridStickyHeader ??
                    FanzineStickyHeader(
                      authState: component.authState,
                      authBloc: component.authBloc,
                    ),
                hasCover: component.hasCover,
                onPageTap: _switchToSingle,
              )
            ],
          ),
        if (!isGrid)
          div(
            id: 'fanzine-list-area',
            classes: listClasses,
            events: {
              'scroll': (e) => _handleListScroll(),
              'wheel': (e) {
                _cancelProgrammaticScroll();
                _activeScrollSource = 2;
              },
              'touchstart': (e) {
                _cancelProgrammaticScroll();
                _activeScrollSource = 2;
              },
              'pointerdown': (e) {
                _cancelProgrammaticScroll();
                _activeScrollSource = 2;
              },
            },
            [
              FanzineListRenderer(
                fanzineId: component.frefFanzineId,
                shortCode: component.shortCode,
                fanzineType: component.fanzineType,
                fanzineTitle: resolvedTitle,
                isColumn1Open: isColumn1Open,
                stickyHeaderWidget: component.listStickyHeader,
                pages: component.pages,
                headerWidget: activeListHeader,
                activeGlobalPanel: _activeGlobalPanel,
                onTogglePanel: _handleTogglePanel,
                onOpenGrid: enableTwoPage ? _switchToGrid : null,
                initialIndex: _listTargetIndex,
                preloadedImageStats: component.preloadedImageStats,
                likedImageIds: component.likedImageIds,
                authState: component.authState,
                authBloc: component.authBloc,
                isEditingMode: component.isEditingMode,
                activeScope: component.activeScope,
              )
            ],
          ),
        if (showThirdColumn)
          div(
            id: 'fanzine-panel-area',
            classes: 'flex-1 h-full overflow-hidden hidden-on-mobile',
            attributes: const {
              'style': 'border-left: 1px solid #d1d5db; background-color: #e5e5e5;'
            },
            [
              PanelColumnRenderer(
                fanzineId: component.frefFanzineId,
                pages: component.pages,
                activePanel: _activeGlobalPanel!,
                isEditingMode: component.isEditingMode,
                targetIndex: _panelTargetIndex,
                onPageCardTap: _handlePanelCardTap,
                onTargetChanged: _updateTargetFromColumn3,
                onScroll: () {},
                onUserScrollStart: () {
                  _cancelProgrammaticScroll();
                  _activeScrollSource = 3;
                },
                onClose: () => setState(() => _activeGlobalPanel = null),
              )
            ],
          )
      ],
    );
  }
}