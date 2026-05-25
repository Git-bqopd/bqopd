import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'readers/fanzine_grid_renderer.dart';
import 'readers/fanzine_list_renderer.dart';
import 'readers/panel_column_renderer.dart';
import 'package:bqopd_core/bqopd_core.dart';

enum FanzineViewMode { grid, single }

/// Jaspr Web Layout component utilizing Set-based likedImageIds to prevent WebSocket connection storms.
class FanzineLayout extends StatefulComponent {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Component gridHeader;
  final Component listHeader;
  final bool hasCover;
  final int? initialPageNumber;
  final Map<String, Map<String, dynamic>> preloadedImageStats;
  final Set<String> likedImageIds; // Pass down Set state
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool isEditingMode;

  const FanzineLayout({
    required this.fanzineId,
    required this.pages,
    required this.gridHeader,
    required this.listHeader,
    this.hasCover = true,
    this.initialPageNumber,
    this.preloadedImageStats = const {},
    required this.likedImageIds,
    this.authState,
    this.authBloc,
    this.isEditingMode = false,
    super.key,
  });

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
    // Default to the split-screen view in editing mode so both grid and list are visible side-by-side
    if (component.isEditingMode) {
      _viewMode = FanzineViewMode.single;
    }
    if (component.initialPageNumber != null && component.initialPageNumber! > 0) {
      _targetIndex = component.initialPageNumber!;
      _viewMode = FanzineViewMode.single;
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
    final isGrid = _viewMode == FanzineViewMode.grid;
    final showThirdColumn = !isGrid && _activeGlobalPanel != null;

    final String calcWidth = "calc((100vh - 120px) * 0.625)";

    return div(classes: 'reader-split-layout', [
      // Column 1: Grid Area
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
            classes: 'list-area',
            attributes: {
              'style': 'flex: 0 0 $calcWidth; min-width: 400px; margin: 0;' // Centered together, no margin auto-split
            },
            [
              FanzineListRenderer(
                fanzineId: component.fanzineId,
                pages: component.pages,
                headerWidget: component.listHeader,
                activeGlobalPanel: _activeGlobalPanel,
                onTogglePanel: _handleTogglePanel,
                onOpenGrid: _switchToGrid,
                initialIndex: _targetIndex,
                preloadedImageStats: component.preloadedImageStats,
                likedImageIds: component.likedImageIds, // Pass down to list
                authState: component.authState,
                authBloc: component.authBloc,
                isEditingMode: component.isEditingMode,
              )
            ]
        ),

      // Column 3: Social/Interaction Panel
      if (showThirdColumn)
        div(
            classes: 'flex-1 bg-white h-full overflow-y-auto hidden-on-mobile',
            attributes: {'style': 'border-left: 1px solid #e0e0e0;'},
            [
              PanelColumnRenderer(
                fanzineId: component.fanzineId,
                pages: component.pages,
                activePanel: _activeGlobalPanel!,
                onClose: () => setState(() => _activeGlobalPanel = null),
              )
            ]
        )
    ]);
  }
}