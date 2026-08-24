import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'readers/fanzine_grid_renderer.dart';
import 'readers/fanzine_list_renderer.dart';
import 'readers/panel_column_renderer.dart';
import 'package:bqopd_core/bqopd_core.dart';

enum FanzineViewMode { grid, single }

/// Jaspr Web Layout component utilizing Set-based likedImageIds to prevent WebSocket connection storms.
class FanzineLayout extends StatefulComponent {
  final String frefFanzineId;
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

  const FanzineLayout({
    required String fanzineId,
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
    super.key,
  }) : frefFanzineId = fanzineId;

  @override
  State<FanzineLayout> createState() => _FanzineLayoutState();
}

class _FanzineLayoutState extends State<FanzineLayout> {
  FanzineViewMode _viewMode = FanzineViewMode.grid;
  int _targetIndex = 0;
  BonusRowType? _activeGlobalPanel;

  @override
  void initState() {
    super.initState();
    if (component.isEditingMode) {
      _viewMode = FanzineViewMode.single;
    }
    if (component.initialPageNumber != null && component.initialPageNumber! > 0) {
      _targetIndex = component.initialPageNumber!;
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

  void _switchToSingle(int index) {
    setState(() {
      _targetIndex = index;
      _viewMode = FanzineViewMode.single;
    });
  }

  void _switchToGrid() {
    setState(() {
      _viewMode = FanzineViewMode.grid;
    });
  }

  void _handleTogglePanel(BonusRowType type) {
    setState(() {
      _activeGlobalPanel = (_activeGlobalPanel == type) ? null : type;
    });
  }

  @override
  Component build(BuildContext context) {
    final bool enableTwoPage = component.twoPage;
    final isGrid = enableTwoPage ? (_viewMode == FanzineViewMode.grid) : false;
    final showThirdColumn = !isGrid && _activeGlobalPanel != null;

    return div(classes: 'reader-split-layout', [
      // Column 1: Grid Area (Spreads over #e5e5e5 grey backdrop)
      if (enableTwoPage)
        div(
            classes: 'grid-area ${!isGrid ? 'hidden-on-mobile' : ''}',
            attributes: {
              'style': isGrid ? 'flex: 1;' : 'flex: 0 0 450px;'
            },
            [
              FanzineGridRenderer(
                pages: component.pages,
                headerWidget: component.gridHeader,
                hasCover: component.hasCover,
                onPageTap: _switchToSingle,
              )
            ]
        ),
      // Column 2: List Area (The Reader)
      if (!isGrid)
        div(
            classes: 'list-area ${component.isEditingMode ? 'editor-mode' : 'reader-mode'} flex-col items-center',
            [
              FanzineListRenderer(
                fanzineId: component.frefFanzineId,
                pages: component.pages,
                headerWidget: component.listHeader,
                activeGlobalPanel: _activeGlobalPanel,
                onTogglePanel: _handleTogglePanel,
                onOpenGrid: enableTwoPage ? _switchToGrid : null,
                initialIndex: _targetIndex,
                preloadedImageStats: component.preloadedImageStats,
                likedImageIds: component.likedImageIds,
                authState: component.authState,
                authBloc: component.authBloc,
                isEditingMode: component.isEditingMode,
              )
            ]
        ),
      // Column 3: Social/Interaction Panel (Grey backdrop matching Column 1)
      if (showThirdColumn)
        div(
            classes: 'flex-1 h-full overflow-y-auto hidden-on-mobile',
            attributes: const {
              'style': 'border-left: 1px solid #d1d5db; background-color: #e5e5e5;'
            },
            [
              PanelColumnRenderer(
                fanzineId: component.frefFanzineId,
                pages: component.pages,
                activePanel: _activeGlobalPanel!,
                isEditingMode: component.isEditingMode,
                onClose: () => setState(() => _activeGlobalPanel = null),
              )
            ]
        )
    ]);
  }
}