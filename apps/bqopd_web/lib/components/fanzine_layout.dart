import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
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
  final List<Map<String, dynamic>> pages;
  final Component gridHeader;
  final Component listHeader;
  final bool hasCover;
  final bool twoPage;
  final int? initialPageNumber;
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
    required this.pages,
    required this.gridHeader,
    required this.listHeader,
    this.hasCover = true,
    this.twoPage = true,
    this.initialPageNumber,
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

  // Distinct target index tracking:
  // _listTargetIndex drives Column 2's current active card.
  // _panelTargetIndex drives Column 3's target card.
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
  }

  @override
  void dispose() {
    _programmaticScrollTimer?.cancel();
    super.dispose();
  }

  void _switchToSingle(int index) {
    _lastFullyInFrameIndex = index;
    final totalItems = component.pages.length + 1;

    // Lock programmatic scrolling so intermediate scroll events do not jerk the columns
    _isProgrammaticScrolling = true;
    _activeScrollSource = 1;
    _programmaticScrollTimer?.cancel();
    _programmaticScrollTimer = Timer(const Duration(milliseconds: 650), () {
      _isProgrammaticScrolling = false;
      _activeScrollSource = 0;
    });

    // Immediately center Column 1 on the clicked item's spread and hold it there
    Future.microtask(() {
      _syncColumn1(index, totalItems);
    });

    // If Column 3 is open and a page item was selected, center the matching card in Column 3
    if (_activeGlobalPanel != null && index > 0) {
      Future.microtask(() {
        centerElementInContainer(
          'panel-column-scroll-area',
          'panel-page-${index - 1}',
          smooth: true,
        );
      });
    }

    // Direct Column 2 to scroll to the chosen page card
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

    // If clicking the active button on the already-targeted page, close the panel
    if (isSamePanelAndTarget) {
      setState(() {
        _activeGlobalPanel = null;
      });
      return;
    }

    _lastFullyInFrameIndex = listIndex;
    final totalItems = component.pages.length + 1;

    // Lock programmatic scrolling so intermediate scroll events do not jerk the columns
    _isProgrammaticScrolling = true;
    _activeScrollSource = 2; // Col 2 interaction
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

    // 1. Center the clicked page's spread in Column 1
    Future.microtask(() {
      _syncColumn1(listIndex, totalItems);
    });

    // 2. Center Column 2 on the corresponding page card
    final String targetId = 'reader-page-$pageIndex';
    scrollToElement(targetId, block: 'center', smooth: true);

    // 3. Align the target widget in Column 3 to the top of the column
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

    // Only synchronize when in split desktop view (Column 1 and Column 2 are both active)
    final bool enableTwoPage = component.twoPage;
    final isGrid = enableTwoPage ? (_viewMode == FanzineViewMode.grid) : false;
    if (isGrid) return;

    // If a programmatic smooth-scroll is active from another column (like Col 3), ignore
    if (_isProgrammaticScrolling && _activeScrollSource != 2) {
      return;
    }

    final totalItems = component.pages.length + 1; // 0 is header, 1..N are pages

    // Delegate DOM container inspection through platform-safe web_utils bridge
    final activeIndex = calculateListScrollActiveIndex(
      containerId: 'fanzine-list-area',
      totalItems: totalItems,
      itemIdBuilder: (i) => i == 0 ? 'fanzine-header' : 'reader-page-${i - 1}',
    );

    // Synchronize ONLY Column 1 when a new widget comes fully into frame
    // RULE: Column 3 is completely untouched when Column 2 is scrolled!
    // CRITICAL: We deliberately avoid calling setState() here so Column 2 maintains
    // uninterrupted native scroll momentum with zero sticking, jittering, or jumps.
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

    // Lock programmatic scrolling for Column 2 so its onscroll doesn't fight
    _isProgrammaticScrolling = true;
    _activeScrollSource = 3;
    _programmaticScrollTimer?.cancel();
    _programmaticScrollTimer = Timer(const Duration(milliseconds: 650), () {
      _isProgrammaticScrolling = false;
      _activeScrollSource = 0;
    });

    // RULE: Scrolling in Column 3 keeps BOTH Column 1 and Column 2 auto centered to their matching widgets
    // 1. Center Column 2 on the corresponding page card
    final String targetId = 'reader-page-$pageIndex';
    scrollToElement(targetId, block: 'center', smooth: true);

    // 2. Center Column 1 on the corresponding spread
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

    // Center the tapped card in Column 3
    centerElementInContainer(
      'panel-column-scroll-area',
      'panel-page-$pageIndex',
      smooth: true,
    );

    // Center the page card in Column 2
    final String targetId = 'reader-page-$pageIndex';
    scrollToElement(targetId, block: 'center', smooth: true);

    // Center the spread in Column 1
    final totalItems = component.pages.length + 1;
    _syncColumn1(listIndex, totalItems);
  }

  void _syncColumn1(int itemIndex, int totalItems) {
    final bool hasCover = component.hasCover;

    // First image or header envelope: scroll Column 1 all the way to top
    if (itemIndex == 0 || (hasCover && itemIndex == 1)) {
      scrollContainerToTop('fanzine-grid-area', smooth: true);
      return;
    }

    // Last image: scroll Column 1 all the way to bottom
    if (itemIndex == totalItems - 1) {
      scrollContainerToBottom('fanzine-grid-area', smooth: true);
      return;
    }

    // Intermediate pages: center the corresponding spread vertically in Column 1
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
    final isGrid = enableTwoPage ? (_viewMode == FanzineViewMode.grid) : false;
    final showThirdColumn = !isGrid && _activeGlobalPanel != null;

    return div(classes: 'reader-split-layout', [
      // Column 1 (Left): Independent scroll with zero side-effects on Column 2 or 3
      if (enableTwoPage)
        div(
          id: 'fanzine-grid-area',
          classes: 'grid-area ${!isGrid ? 'hidden-on-mobile' : ''}',
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
              headerWidget: component.gridHeader,
              hasCover: component.hasCover,
              onPageTap: _switchToSingle,
            )
          ],
        ),
      // Column 2 (Center): Scrolling keeps Column 1 centered, leaves Column 3 untouched
      if (!isGrid)
        div(
          id: 'fanzine-list-area',
          classes: 'list-area ${component.isEditingMode ? 'editor-mode' : 'reader-mode'} flex-col items-center',
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
              pages: component.pages,
              headerWidget: component.listHeader,
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
      // Column 3 (Right): Scrolling auto-centers both Column 1 and Column 2 to their matching widgets
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
    ]);
  }
}