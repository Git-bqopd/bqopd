import 'dart:async';
import 'dart:math' as math;
import 'dart:js_interop';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:web/web.dart' as web;

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
/// Implements a physical horizontal target line indicator that glides between
/// widget midpoints and the vertical viewport center line.
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
    super.key,
  });

  @override
  State<MultiPageColumnLayout> createState() => _MultiPageColumnLayoutState();
}

class _MultiPageColumnLayoutState extends State<MultiPageColumnLayout> {
  int _currentTargetIndex = 0;
  double _lineY = -1.0;
  bool _isLineLockedAtCenter = false;
  web.HTMLDivElement? _scrollAreaEl;
  JSFunction? _wheelListener;

  @override
  void initState() {
    super.initState();
    _currentTargetIndex = component.targetPageIndex ?? 0;
    if (kIsWeb) {
      Future.microtask(() {
        _attachNativeWheelListener();
        _syncLineWithTarget();
      });
    }
  }

  @override
  void didUpdateComponent(MultiPageColumnLayout oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.targetPageIndex != component.targetPageIndex &&
        component.targetPageIndex != null) {
      if (component.targetPageIndex != _currentTargetIndex) {
        _currentTargetIndex = component.targetPageIndex!;
        if (kIsWeb) {
          Future.microtask(() {
            _syncLineWithTarget();
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _detachNativeWheelListener();
    super.dispose();
  }

  void _attachNativeWheelListener() {
    final el = web.document.getElementById('panel-column-scroll-area')
    as web.HTMLDivElement?;
    if (el == null) return;
    _scrollAreaEl = el;

    final jsHandler = ((web.WheelEvent e) {
      _handleWheel(e);
    }).toJS;
    _wheelListener = jsHandler;

    // Use non-passive listener (false) so preventDefault() can stop page scrolling while the line moves
    el.addEventListener('wheel', jsHandler, false.toJS);
  }

  void _detachNativeWheelListener() {
    if (_scrollAreaEl != null && _wheelListener != null) {
      _scrollAreaEl!.removeEventListener('wheel', _wheelListener!, false.toJS);
      _wheelListener = null;
      _scrollAreaEl = null;
    }
  }

  double? _getCardCenterY(int pageIndex) {
    final scrollArea = web.document.getElementById('panel-column-scroll-area');
    final card = web.document.getElementById('panel-page-$pageIndex');
    if (scrollArea == null || card == null) return null;
    final areaRect = scrollArea.getBoundingClientRect();
    final cardRect = card.getBoundingClientRect();
    return (cardRect.top - areaRect.top) + (cardRect.height / 2.0);
  }

  void _syncLineWithTarget({int tries = 6}) {
    if (!kIsWeb) return;
    final scrollArea = web.document.getElementById('panel-column-scroll-area');
    final card = web.document.getElementById('panel-page-$_currentTargetIndex');
    if (scrollArea != null &&
        card != null &&
        card.getBoundingClientRect().height > 0) {
      _alignLineToTarget();
      return;
    }
    if (tries > 0) {
      web.window.setTimeout((() {
        _syncLineWithTarget(tries: tries - 1);
      }).toJS, 40.toJS);
    }
  }

  void _alignLineToTarget() {
    if (!kIsWeb) return;
    final scrollArea = web.document.getElementById('panel-column-scroll-area');
    if (scrollArea == null) return;
    final double areaHeight = scrollArea.clientHeight.toDouble();
    if (areaHeight <= 0) return;
    final double viewportCenter = areaHeight / 2.0;

    final cardCenter = _getCardCenterY(_currentTargetIndex);
    if (cardCenter != null) {
      _lineY = cardCenter;
      final diffFromCenter = (_lineY - viewportCenter).abs();
      _isLineLockedAtCenter = diffFromCenter <= 6.0;
      if (_isLineLockedAtCenter) {
        _lineY = viewportCenter;
      }
      _updateLineDOM();
      _updateCardHighlightsDOM();
    }
  }

  void _handleWheel(web.WheelEvent e) {
    if (component.onUserScrollStart != null) {
      component.onUserScrollStart!();
    }

    final scrollArea = web.document.getElementById('panel-column-scroll-area');
    if (scrollArea == null) return;

    final double areaHeight = scrollArea.clientHeight.toDouble();
    if (areaHeight <= 0) return;
    final double viewportCenter = areaHeight / 2.0;
    final double scrollTop = scrollArea.scrollTop.toDouble();
    final double maxScrollTop =
    (scrollArea.scrollHeight - scrollArea.clientHeight).toDouble();
    final bool isAtTop = scrollTop <= 2.0;
    final bool isAtBottom = scrollTop >= (maxScrollTop - 4.0);

    final double delta = e.deltaY.toDouble();
    if (delta == 0) return;

    final totalPages = component.pages.length;
    final topCardCenter = _getCardCenterY(0) ?? 16.0;
    final bottomCardCenter =
        _getCardCenterY(totalPages - 1) ?? (areaHeight - 16.0);

    if (!_isLineLockedAtCenter) {
      // Phase 1: Line is moving towards or away from the viewport vertical center
      if (_lineY < viewportCenter) {
        // Line is currently above center
        if (delta > 0) {
          // Scrolling down (towards center) -> move line down, NOT page
          e.preventDefault();
          _lineY += delta;
          if (_lineY >= viewportCenter) {
            _lineY = viewportCenter;
            _isLineLockedAtCenter = true;
          }
          _onLinePositionChanged();
        } else {
          // Scrolling up (away from center towards top widget midpoint)
          e.preventDefault();
          _lineY = math.max(topCardCenter, _lineY + delta);
          _onLinePositionChanged();
        }
      } else {
        // Line is currently below center
        if (delta < 0) {
          // Scrolling up (towards center) -> move line up, NOT page
          e.preventDefault();
          _lineY += delta;
          if (_lineY <= viewportCenter) {
            _lineY = viewportCenter;
            _isLineLockedAtCenter = true;
          }
          _onLinePositionChanged();
        } else {
          // Scrolling down (away from center towards bottom widget midpoint)
          e.preventDefault();
          _lineY = math.min(bottomCardCenter, _lineY + delta);
          _onLinePositionChanged();
        }
      }
    } else {
      // Phase 2: Line is locked at viewport center
      if (delta < 0 && isAtTop) {
        // Scrolled all the way to the top boundary: move line up towards top widget midpoint
        if (topCardCenter < viewportCenter) {
          e.preventDefault();
          _lineY = math.max(topCardCenter, _lineY + delta);
          if (_lineY < viewportCenter) {
            _isLineLockedAtCenter = false;
          }
          _onLinePositionChanged();
        }
      } else if (delta > 0 && isAtBottom) {
        // Scrolled all the way to the bottom boundary: move line down towards bottom widget midpoint
        if (bottomCardCenter > viewportCenter) {
          e.preventDefault();
          _lineY = math.min(bottomCardCenter, _lineY + delta);
          if (_lineY > viewportCenter) {
            _isLineLockedAtCenter = false;
          }
          _onLinePositionChanged();
        }
      } else {
        // Normal scrolling: line stays locked at viewport center
        _lineY = viewportCenter;
        _updateLineDOM();
      }
    }
  }

  void _handleScroll() {
    if (component.onScroll != null) {
      component.onScroll!();
    }
    final scrollArea = web.document.getElementById('panel-column-scroll-area');
    if (scrollArea == null) return;
    final double areaHeight = scrollArea.clientHeight.toDouble();
    final double viewportCenter = areaHeight / 2.0;

    if (_isLineLockedAtCenter) {
      _lineY = viewportCenter;
      _updateLineDOM();
      final cardIdx = _findCardUnderLine(_lineY);
      if (cardIdx != null && cardIdx != _currentTargetIndex) {
        _currentTargetIndex = cardIdx;
        _updateCardHighlightsDOM();
        if (component.onTargetChanged != null) {
          component.onTargetChanged!(cardIdx);
        }
      }
    }
  }

  void _onLinePositionChanged() {
    _updateLineDOM();
    final cardIdx = _findCardUnderLine(_lineY);
    if (cardIdx != null && cardIdx != _currentTargetIndex) {
      _currentTargetIndex = cardIdx;
      _updateCardHighlightsDOM();
      if (component.onTargetChanged != null) {
        component.onTargetChanged!(cardIdx);
      }
    }
  }

  int? _findCardUnderLine(double lineY) {
    final scrollArea = web.document.getElementById('panel-column-scroll-area');
    if (scrollArea == null) return null;
    final areaRect = scrollArea.getBoundingClientRect();
    final totalPages = component.pages.length;

    for (int i = 0; i < totalPages; i++) {
      final card = web.document.getElementById('panel-page-$i');
      if (card != null) {
        final cardRect = card.getBoundingClientRect();
        final cardTop = cardRect.top - areaRect.top;
        final cardBottom = cardRect.bottom - areaRect.top;
        if (lineY >= cardTop && lineY <= cardBottom) {
          return i;
        }
      }
    }

    // Fallback: choose whichever card's center midpoint is closest
    int closestIdx = 0;
    double minDiff = 999999.0;
    for (int i = 0; i < totalPages; i++) {
      final center = _getCardCenterY(i);
      if (center != null) {
        final diff = (center - lineY).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestIdx = i;
        }
      }
    }
    return closestIdx;
  }

  void _updateLineDOM() {
    final line = web.document.getElementById('panel-target-indicator-line')
    as web.HTMLDivElement?;
    if (line != null && _lineY >= 0) {
      line.style.top = '${_lineY.toStringAsFixed(1)}px';
      line.style.display = 'flex';
    }
  }

  void _updateCardHighlightsDOM() {
    for (int i = 0; i < component.pages.length; i++) {
      final el = web.document.getElementById('panel-page-$i')
      as web.HTMLDivElement?;
      if (el != null) {
        if (i == _currentTargetIndex) {
          el.classList.remove('non-target');
          el.classList.add('target');
        } else {
          el.classList.remove('target');
          el.classList.add('non-target');
        }
      }
    }
  }

  void _handleCardTap(int i) {
    _currentTargetIndex = i;
    _updateCardHighlightsDOM();
    if (component.onPageCardTap != null) {
      component.onPageCardTap!(i);
    }
    if (kIsWeb) {
      final scrollArea =
      web.document.getElementById('panel-column-scroll-area');
      if (scrollArea != null) {
        final double areaHeight = scrollArea.clientHeight.toDouble();
        final double viewportCenter = areaHeight / 2.0;
        _lineY = viewportCenter;
        _isLineLockedAtCenter = true;
        _updateLineDOM();
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
        // Relative Viewport Wrapper hosting Scroll Area and Absolute Reticle Line
        div(
          id: 'panel-column-viewport-wrapper',
          attributes: const {
            'style':
            'position: relative; flex: 1; width: 100%; height: 100%; overflow: hidden; display: flex; flex-direction: column;'
          },
          [
            // The Horizontal Target Indicator Line
            div(
              id: 'panel-target-indicator-line',
              classes: 'panel-target-indicator-line',
              attributes: const {
                'style': 'top: 0px; display: none;'
              },
              [],
            ),
            // Scrollable Feed List (#e5e5e5 backdrop with bottom padding buffer)
            div(
              id: 'panel-column-scroll-area',
              classes: 'flex-1 overflow-y-auto p-4',
              attributes: const {
                'style':
                'flex: 1; overflow-y: auto; padding: 16px; padding-bottom: calc(100vh - 180px); background-color: #e5e5e5;'
              },
              events: {
                'scroll': (e) => _handleScroll(),
                if (component.onUserScrollStart != null)
                  'touchstart': (e) => component.onUserScrollStart!(),
                if (component.onUserScrollStart != null)
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
                      attributes: const {
                        'style':
                        'background-color: #ffffff; border-radius: 8px; padding: 20px; margin-bottom: 20px;'
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
                                    'font-size: 10px; color: #6750A4; font-weight: bold; letter-spacing: 0.5px; text-transform: uppercase;',
                                  },
                                  [Component.text('ACTIVE')],
                                ),
                            ],
                          ),
                        // Page Widget Content with padding around comments/info
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