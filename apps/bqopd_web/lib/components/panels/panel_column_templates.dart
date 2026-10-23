import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_utils.dart';

/// Template layout for singleton tools that occupy the entire column width and height
/// without repeating per page (e.g. Terminal, YouTube, Settings, Analytics).
class SingleWindowColumnLayout extends StatelessComponent {
  final String title;
  final Component child;
  final VoidCallback onClose;

  const SingleWindowColumnLayout({
    required this.title,
    required this.child,
    required this.onClose,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'w-full h-full flex-col overflow-hidden',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; width: 100%; height: 100%; overflow: hidden; background-color: #e5e5e5;'
      },
      [
// Column Header
        div(
          classes: 'p-4 bg-white flex-row justify-between items-center',
          attributes: const {
            'style':
            'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #d1d5db; flex-shrink: 0; padding: 16px; background-color: #ffffff;'
          },
          [
            span(
              [Component.text(title)],
              attributes: const {
                'style':
                'font-weight: bold; font-size: 13px; letter-spacing: 0.8px; text-transform: uppercase; color: #1e293b;'
              },
            ),
            button(
              classes: 'cursor-pointer border-none bg-transparent',
              events: {'click': (e) => onClose()},
              [
                span(
                  classes: 'material-symbols-outlined',
                  [Component.text('close')],
                )
              ],
            )
          ],
        ),
// Body area (Grey background #e5e5e5)
        div(
          id: 'panel-singleton-scroll-area',
          classes: 'flex-1 overflow-y-auto p-4',
          attributes: const {
            'style':
            'flex: 1; overflow-y: auto; padding: 16px; background-color: #e5e5e5;'
          },
          [child],
        )
      ],
    );
  }
}

/// Template layout for per-page panels that iterate through each page in the fanzine
/// (e.g. Comments, Text Reader, OCR Text, Entities, Credits).
///
/// Features a native, unconstrained list scroll feed where scrolling in this column
/// does not trigger or hijack scrolling in Columns 1 and 2.
/// Visually highlights the active target card and switches the target upon clicking.
class MultiPageColumnLayout extends StatefulComponent {
  final String title;
  final List<Map<String, dynamic>> pages;
  final Component Function(Map<String, dynamic> pageData) pageBuilder;
  final VoidCallback onClose;
  final Component? headerWidget;
  final int? targetPageIndex;
  final Function(int pageIndex)? onPageCardTap;
  final Function(int pageIndex)? onTargetChanged;
  final VoidCallback? onScroll;
  final VoidCallback? onUserScrollStart;
  final bool simpleScroll;

  const MultiPageColumnLayout({
    required this.title,
    required this.pages,
    required this.pageBuilder,
    required this.onClose,
    this.headerWidget,
    this.targetPageIndex,
    this.onPageCardTap,
    this.onTargetChanged,
    this.onScroll,
    this.onUserScrollStart,
    this.simpleScroll = true,
    super.key,
  });

  @override
  State createState() => _MultiPageColumnLayoutState();
}

class _MultiPageColumnLayoutState extends State {
  @override
  MultiPageColumnLayout get component => super.component as MultiPageColumnLayout;

  int _currentTargetIndex = 0;
  PanelColumnIndicatorCoordinator? _indicatorCoordinator;

  @override
  void initState() {
    super.initState();
    _currentTargetIndex = component.targetPageIndex ?? 0;

    if (!component.simpleScroll) {
      _indicatorCoordinator = PanelColumnIndicatorCoordinator(
        scrollAreaId: 'panel-column-scroll-area',
        lineId: 'panel-target-indicator-line',
        cardPrefix: 'panel-page-',
        totalPages: () => component.pages.length,
        getCurrentTargetIndex: () => _currentTargetIndex,
        onTargetChanged: (newIdx) {
          _currentTargetIndex = newIdx;
          if (component.onTargetChanged != null) {
            component.onTargetChanged!(newIdx);
          }
        },
        onUserScrollStart: () {
          if (component.onUserScrollStart != null) {
            component.onUserScrollStart!();
          }
        },
      );

      if (kIsWeb) {
        Future.microtask(() {
          _indicatorCoordinator?.init();
        });
      }
    }


  }

  @override
  void didUpdateComponent(MultiPageColumnLayout oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.targetPageIndex != component.targetPageIndex &&
        component.targetPageIndex != null) {
      if (component.targetPageIndex != _currentTargetIndex) {
        setState(() {
          _currentTargetIndex = component.targetPageIndex!;
        });
        if (!component.simpleScroll && kIsWeb) {
          Future.microtask(() {
            _indicatorCoordinator?.syncLineWithTarget();
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _indicatorCoordinator?.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (component.onScroll != null) {
      component.onScroll!();
    }
    if (!component.simpleScroll) {
      _indicatorCoordinator?.handleScroll();
    }
  }

  void _handleCardTap(int i) {
    if (_currentTargetIndex != i) {
      setState(() {
        _currentTargetIndex = i;
      });
      if (!component.simpleScroll) {
        _indicatorCoordinator?.handleCardTap(i);
      }
      if (component.onPageCardTap != null) {
        component.onPageCardTap!(i);
      }
    }
  }

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'w-full h-full flex-col overflow-hidden',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; width: 100%; height: 100%; overflow: hidden; background-color: #e5e5e5;'
      },
      [
// Column Header
        div(
          classes: 'p-4 bg-white flex-row justify-between items-center',
          attributes: const {
            'style':
            'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #d1d5db; flex-shrink: 0; padding: 16px; background-color: #ffffff;'
          },
          [
            span(
              [Component.text(component.title)],
              attributes: const {
                'style':
                'font-weight: bold; font-size: 13px; letter-spacing: 0.8px; text-transform: uppercase; color: #1e293b;'
              },
            ),
            button(
              classes: 'cursor-pointer border-none bg-transparent',
              events: {'click': (e) => component.onClose()},
              [
                span(
                  classes: 'material-symbols-outlined',
                  [Component.text('close')],
                )
              ],
            )
          ],
        ),
// Relative Viewport Wrapper hosting Scroll Area
        div(
          id: 'panel-column-viewport-wrapper',
          attributes: const {
            'style':
            'position: relative; flex: 1; width: 100%; height: 100%; overflow: hidden; display: flex; flex-direction: column;'
          },
          [
// The Horizontal Target Indicator Line (rendered only when using synchronized coordinator)
            if (!component.simpleScroll)
              div(
                id: 'panel-target-indicator-line',
                classes: 'panel-target-indicator-line',
                attributes: const {
                  'style': 'top: 0px; display: none;'
                },
                [],
              ),
// Scrollable Feed List
            div(
              id: 'panel-column-scroll-area',
              classes: 'flex-1 overflow-y-auto p-4',
              attributes: {
                'style': component.simpleScroll
                    ? 'flex: 1; overflow-y: auto; padding: 16px; background-color: #e5e5e5; -webkit-overflow-scrolling: touch;'
                    : 'flex: 1; overflow-y: auto; padding: 16px; padding-bottom: calc(100vh - 180px); background-color: #e5e5e5;'
              },
              events: {
                if (!component.simpleScroll) 'scroll': (e) => _handleScroll(),
                if (!component.simpleScroll && component.onUserScrollStart != null)
                  'touchstart': (e) => component.onUserScrollStart!(),
                if (!component.simpleScroll && component.onUserScrollStart != null)
                  'pointerdown': (e) => component.onUserScrollStart!(),
              },
              [
// Optional Top Column Widget (e.g. EntitiesColumnPanelHeader map)
                if (component.headerWidget != null) component.headerWidget!,
                for (int i = 0; i < component.pages.length; i++) ...[
                      () {
                    final page = component.pages[i];
                    final bool isTarget = (_currentTargetIndex == i);

                    return div(
                      id: 'panel-page-$i',
                      classes:
                      'panel-page-card bg-white rounded-lg border shadow-md p-5 mb-5 ${isTarget ? "target" : "non-target"}',
                      attributes: {
                        'style':
                        'background-color: #ffffff; border-radius: 8px; padding: 20px; margin-bottom: 20px; cursor: pointer; transition: all 0.2s ease; ${isTarget ? "border: 2px solid #6750A4; box-shadow: 0 4px 16px rgba(103, 80, 164, 0.16);" : "border: 1px solid #cbd5e1;"}',
                      },
                      events: {
                        'click': (e) => _handleCardTap(i),
                      },
                      [
                        // Page Card Header Banner
                        if (page['pageNumber'] != null)
                          div(
                            classes:
                            'flex-row items-center justify-between border-b border-gray-200 pb-2 mb-4',
                            attributes: const {
                              'style':
                              'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; margin-bottom: 16px;'
                            },
                            [
                              span(
                                classes:
                                'text-xs font-bold uppercase tracking-wider',
                                attributes: {
                                  'style':
                                  'font-size: 11px; font-weight: bold; color: ${isTarget ? "#6750A4" : "#475569"}; letter-spacing: 0.8px; text-transform: uppercase;',
                                },
                                [Component.text('PAGE ${page['pageNumber']}')],
                              ),
                              if (isTarget)
                                span(
                                  classes: 'text-xs font-bold',
                                  attributes: const {
                                    'style':
                                    'font-size: 10px; color: #6750A4; font-weight: bold; letter-spacing: 0.5px; text-transform: uppercase; background-color: #E8DEF8; padding: 2px 8px; border-radius: 10px;',
                                  },
                                  [Component.text('ACTIVE')],
                                ),
                            ],
                          ),
                        // Page Widget Content
                        div(
                          attributes: const {'style': 'padding: 4px;'},
                          [component.pageBuilder(page)],
                        ),
                      ],
                    );
                  }(),
                ]
              ],
            )
          ],
        )
      ],
    );


  }
}