import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'readers/fanzine_grid_renderer.dart';
import 'readers/fanzine_list_renderer.dart';

enum FanzineViewMode { grid, single }

class FanzineLayout extends StatefulComponent {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Component headerWidget;
  final bool hasCover;

  const FanzineLayout({
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    this.hasCover = true,
  });

  @override
  State<FanzineLayout> createState() => _FanzineLayoutState();
}

class _FanzineLayoutState extends State<FanzineLayout> {
  FanzineViewMode _viewMode = FanzineViewMode.grid;
  int _targetIndex = 0;

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

  @override
  Component build(BuildContext context) {
    final isGrid = _viewMode == FanzineViewMode.grid;

    return div(classes: 'reader-split-layout', [
      // Left side: Grid Area (Turns into a fixed sidebar when in List mode on Desktop)
      div(
          classes: 'grid-area ${!isGrid ? 'hidden-on-mobile' : ''}',
          attributes: {
            'style': isGrid ? 'flex: 1;' : 'flex: 0 0 450px;'
          },
          [
            FanzineGridRenderer(
              pages: component.pages,
              headerWidget: component.headerWidget,
              hasCover: component.hasCover,
              onPageTap: _switchToSingle,
            )
          ]
      ),

      // Right side: List Area
      if (!isGrid)
        div(
            classes: 'list-area',
            attributes: {
              'style': 'flex: 1; max-width: 800px; margin: 0 auto;'
            },
            [
              div(classes: 'flex justify-end mb-4', [
                button(
                    classes: 'nav-pill',
                    events: {'click': (e) => _switchToGrid()},
                    [text('Close')]
                )
              ]),
              FanzineListRenderer(
                fanzineId: component.fanzineId,
                pages: component.pages,
                headerWidget: component.headerWidget,
                onOpenGrid: _switchToGrid,
              )
            ]
        )
    ]);
  }
}