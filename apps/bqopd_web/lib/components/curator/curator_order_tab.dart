import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../segmented_button.dart';

/// Curator-only flatplan sequence order and spread/side preference configuration tab.
/// Decoupled from the Editor to allow curator-only layout constraints and flow rules.
class CuratorOrderTab extends StatelessComponent {
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final FanzineEditorBloc bloc;

  const CuratorOrderTab({
    required this.fanzine,
    required this.pages,
    required this.bloc,
    super.key,
  });

  bool _isPage5x8(FanzinePage page) {
    if (page.templateId != null) return true;
    final w = page.width;
    final h = page.height;
    if (w != null && h != null && w != 0 && h != 0) {
      final ratio = w / h;
      return ratio >= 0.58 && ratio <= 0.67;
    }
    return true; // Web asset default fallback
  }

  void _onSpreadPosChanged(FanzinePage page, int idx, List<FanzinePage> fullPages, String clickedVal) {
    final String currentSpreadPos = page.spreadPosition ?? '';

    if (clickedVal == 'start') {
      if (currentSpreadPos == 'start') {
        _disassembleSpread(idx, idx + 1, fullPages, 'either', 'either');
      } else {
        if (idx < fullPages.length - 1) {
          _assembleSpread(idx, idx + 1, fullPages);
        }
      }
    } else if (clickedVal == 'end') {
      if (currentSpreadPos == 'end') {
        _disassembleSpread(idx, idx - 1, fullPages, 'either', 'either');
      } else {
        if (idx > 0) {
          _assembleSpread(idx - 1, idx, fullPages);
        }
      }
    }
  }

  void _onSidePrefChanged(FanzinePage page, int idx, List<FanzinePage> fullPages, String clickedVal) {
    final String currentSpreadPos = page.spreadPosition ?? '';

    if (currentSpreadPos == 'start') {
      if (clickedVal != 'left') {
        _disassembleSpread(idx, idx + 1, fullPages, clickedVal, 'either');
      } else {
        bloc.add(UpdatePageLayoutRequested(page, 'start', 'left', pages));
      }
    } else if (currentSpreadPos == 'end') {
      if (clickedVal != 'right') {
        _disassembleSpread(idx, idx - 1, fullPages, clickedVal, 'either');
      } else {
        bloc.add(UpdatePageLayoutRequested(page, 'end', 'right', pages));
      }
    } else {
      bloc.add(UpdatePageLayoutRequested(page, null, clickedVal, pages));
    }
  }

  void _assembleSpread(int startIdx, int endIdx, List<FanzinePage> fullPages) {
    if (startIdx < 0 || endIdx >= fullPages.length) return;
    bloc.add(UpdatePageLayoutRequested(fullPages[startIdx], 'start', 'left', pages));
    bloc.add(UpdatePageLayoutRequested(fullPages[endIdx], 'end', 'right', pages));
  }

  void _disassembleSpread(int activeIdx, int siblingIdx, List<FanzinePage> fullPages, String activeTargetSide, String siblingTargetSide) {
    bloc.add(UpdatePageLayoutRequested(fullPages[activeIdx], null, activeTargetSide, pages));
    if (siblingIdx >= 0 && siblingIdx < fullPages.length) {
      bloc.add(UpdatePageLayoutRequested(fullPages[siblingIdx], null, siblingTargetSide, pages));
    }
  }

  @override
  Component build(BuildContext context) {
    final fullPages = pages.where((p) => _isPage5x8(p)).toList();

    if (fullPages.isEmpty) {
      return div(
        [
          span([text('format_list_numbered')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
          p([text('No pages added to fanzine flatplan yet.')])
        ],
        classes: 'p-16 text-center text-gray italic',
      );
    }

    return div(
      [
        h2(
          [text('Folio Flatplan Sequence')],
          classes: 'text-sm font-bold text-gray uppercase tracking-wider mb-3',
        ),

        for (int i = 0; i < fullPages.length; i++)
          _buildOrderPageRow(fullPages[i], i, fullPages.length, fullPages)
      ],
      classes: 'flex-col gap-3 text-left p-2',
    );
  }

  Component _buildOrderPageRow(FanzinePage page, int idx, int totalCount, List<FanzinePage> fullPages) {
    final String? optimalUrl = page.gridUrl ?? page.listUrl ?? page.imageUrl;
    final bool isPending = optimalUrl == null || optimalUrl.isEmpty;
    final String? templateId = page.templateId;

    final String selectedSpreadPos = page.spreadPosition ?? '';
    final String selectedSidePref = page.sidePreference;

    final bool isPage1Cover = idx == 0 && fanzine.hasCover;

    Component layoutButtonsComponent = !isPage1Cover
        ? SegmentedButton<String>(
      segments: const ['start', 'end'],
      selected: selectedSpreadPos,
      labelBuilder: (val) => val,
      onSelectionChanged: (val) {
        _onSpreadPosChanged(page, idx, fullPages, val);
      },
    )
        : div([], attributes: const {'style': 'width: 140px;'});

    Component sidePreferenceComponent = SegmentedButton<String>(
      segments: const ['left', 'either', 'right'],
      selected: isPage1Cover ? 'right' : selectedSidePref,
      labelBuilder: (val) => val,
      onSelectionChanged: (val) {
        if (isPage1Cover) return;
        _onSidePrefChanged(page, idx, fullPages, val);
      },
    );

    Component coverSwitchComponent = idx == 0
        ? div(
      [
        span([text('cover')], attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #49454F; margin-right: 6px;'}),
        _buildCustomToggleSwitchForCover(fanzine.hasCover),
      ],
      attributes: const {
        'style': 'display: inline-flex; align-items: center; margin-left: auto;'
      },
      events: {
        'click': (e) {
          final nextVal = !fanzine.hasCover;
          bloc.add(ToggleHasCoverRequested(nextVal));

          if (nextVal) {
            bloc.add(UpdatePageLayoutRequested(page, null, 'right', pages));
          } else {
            bloc.add(UpdatePageLayoutRequested(page, null, 'either', pages));
          }
        }
      },
    )
        : div([]);

    return div(
      [
        // Top row
        div(
          [
            div(
              [
                span(
                  [text('${idx + 1}.')],
                  classes: 'font-black text-xs text-gray-400',
                  attributes: const {'style': 'width: 20px; text-align: right; margin-right: 8px; display: inline-block;'},
                ),
                div(
                  [
                    if (templateId == 'basic_text')
                      div([
                        span([text('description')], classes: 'material-symbols-outlined', attributes: const {
                          'style': 'font-size: 16px; color: #6750A4;'
                        })
                      ], classes: 'w-full h-full flex items-center justify-center')
                    else if (templateId == 'calendar_left' || templateId == 'calendar_right')
                      div([
                        span([text('calendar_today')], classes: 'material-symbols-outlined', attributes: const {
                          'style': 'font-size: 16px; color: #6750A4;'
                        })
                      ], classes: 'w-full h-full flex items-center justify-center')
                    else if (!isPending)
                        img(
                            src: optimalUrl,
                            attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'}
                        )
                      else
                        div(
                          [
                            span(
                              [text('progress_activity')],
                              classes: 'material-symbols-outlined text-gray-300',
                              attributes: const {'style': 'font-size: 16px;'},
                            )
                          ],
                          classes: 'shimmer-bg w-full h-full flex items-center justify-center',
                        )
                  ],
                  classes: 'rounded border border-gray-200 overflow-hidden bg-white',
                  attributes: const {'style': 'width: 36px; height: 50px; position: relative; display: inline-block; vertical-align: middle; margin-right: 12px;'},
                ),
                span(
                  [
                    text(templateId == 'basic_text'
                        ? 'Generated Text Page'
                        : (templateId != null && templateId.startsWith('calendar')
                        ? 'Generated Calendar Page'
                        : (isPending ? 'Processing web asset...' : 'Archival Page')))
                  ],
                  classes: 'text-xs font-bold text-gray-700',
                  attributes: const {'style': 'display: inline-block; vertical-align: middle;'},
                )
              ],
              attributes: const {'style': 'display: flex; align-items: center;'},
            ),

            // Page positioning and deletions
            div(
              [
                button(
                  [span([text('arrow_upward')], classes: 'material-symbols-outlined text-sm')],
                  classes: 'p-1 hover:bg-gray-100 rounded border-none bg-transparent cursor-pointer',
                  attributes: (idx == 0) ? {'disabled': 'true'} : const {},
                  events: {'click': (e) => bloc.add(ReorderPageRequested(page, -1, pages))},
                ),
                button(
                  [span([text('arrow_downward')], classes: 'material-symbols-outlined text-sm')],
                  classes: 'p-1 hover:bg-gray-100 rounded border-none bg-transparent cursor-pointer',
                  attributes: (idx >= totalCount - 1) ? {'disabled': 'true'} : const {},
                  events: {'click': (e) => bloc.add(ReorderPageRequested(page, 1, pages))},
                ),
                span([text('|')], classes: 'px-1 text-gray-300', attributes: const {'style': 'margin: 0 4px;'}),
                button(
                  [span([text('close')], classes: 'material-symbols-outlined text-sm text-red-500')],
                  classes: 'p-1 hover:bg-red-50 rounded border-none bg-transparent cursor-pointer',
                  events: {'click': (e) => bloc.add(RemovePageRequested(page, pages))},
                ),
              ],
              attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'},
            )
          ],
          classes: 'flex-row items-center justify-between',
          attributes: const {
            'style': 'display: flex; flex-direction: row; justify-content: space-between; align-items: center; width: 100%;'
          },
        ),

        // Controls Segment Row
        div(
          [
            // Column 1: Spread Position
            div(
              [layoutButtonsComponent],
              attributes: const {'style': 'width: 140px; display: flex; align-items: center;'},
            ),

            // Column 2: Side Preference
            div(
              [sidePreferenceComponent],
              attributes: const {'style': 'width: 200px; display: flex; align-items: center;'},
            ),

            // Column 3: Cover
            coverSwitchComponent,
          ],
          classes: 'flex-row flex-wrap justify-between items-center pt-3 border-t border-gray-100',
          attributes: const {
            'style': 'display: flex; flex-direction: row; flex-wrap: wrap; justify-content: flex-start; align-items: center; gap: 16px; border-top: 1px solid #f3f4f6; width: 100%;'
          },
        )
      ],
      classes: 'fanzine-page-row-card',
      attributes: const {
        'style': 'display: flex; flex-direction: column; gap: 12px; border: 1px solid #d1d5db; border-radius: 8px; padding: 16px; background-color: #ffffff; margin-bottom: 16px; box-shadow: 0 1px 2px rgba(0,0,0,0.05);'
      },
    );
  }

  Component _buildCustomToggleSwitchForCover(bool val) {
    return div(
      [],
      attributes: {
        'style': 'width: 33px; height: 18px; border-radius: 10px; background-color: ${val ? '#808080' : '#ccc'}; position: relative; transition: background-color 0.2s; cursor: pointer; display: inline-block;'
      },
    );
  }
}