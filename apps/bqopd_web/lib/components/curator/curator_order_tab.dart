import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Curator-only isolated Order tab for managing sequence, page spreads, and page orientations.
class CuratorOrderTab extends StatefulComponent {
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final FanzineEditorBloc bloc;

  const CuratorOrderTab({
    required this.fanzine,
    required this.pages,
    required this.bloc,
    super.key,
  });

  @override
  State<CuratorOrderTab> createState() => _CuratorOrderTabState();
}

class _CuratorOrderTabState extends State<CuratorOrderTab> {
  bool _isPage5x8(FanzinePage page) {
    if (page.templateId != null) {
      return true;
    }
    final w = page.width;
    final h = page.height;
    if (w != null && h != null && h > 0) {
      final ratio = w / h;
      return ratio >= 0.58 && ratio <= 0.67;
    }
    return true;
  }

  @override
  Component build(BuildContext context) {
    final fullPages = component.pages.where((p) => _isPage5x8(p)).toList();
    final ordered = fullPages.where((p) => p.pageNumber > 0).toList()
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    final unordered = fullPages.where((p) => p.pageNumber == 0).toList();

    return div(
      classes: 'flex-col gap-4 text-left p-2',
      attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px; width: 100%; box-sizing: border-box;'},
      [
        div(
          attributes: const {'style': 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #f0f0f0; padding-bottom: 8px;'},
          [
            span(
              [Component.text('flatplan sequence')],
              attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; letter-spacing: 0.5px;'},
            ),
            span(
              [Component.text('${ordered.length} ordered • ${unordered.length} unordered')],
              attributes: const {'style': 'font-size: 11px; color: #999;'},
            ),
          ],
        ),

        if (ordered.isEmpty)
          div(
            [
              span(
                [Component.text('no pages in the sequence.')],
                attributes: const {'style': 'font-size: 12px; color: #888; font-style: italic;'},
              ),
            ],
            attributes: const {'style': 'padding: 24px; text-align: center; background-color: #fafafa; border-radius: 8px; border: 1px dashed #e0e0e0;'},
          )
        else
          div(
            attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'},
            [
              for (int i = 0; i < ordered.length; i++)
                _buildOrderedPageRow(ordered[i], i, ordered),
            ],
          ),

        if (unordered.isNotEmpty) ...[
          div(
            attributes: const {'style': 'margin-top: 16px; border-top: 1px solid #f0f0f0; padding-top: 12px;'},
            [
              span(
                [Component.text('unordered full pages (${unordered.length})')],
                attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; letter-spacing: 0.5px;'},
              ),
            ],
          ),
          div(
            attributes: const {
              'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); gap: 10px; width: 100%; margin-top: 8px;'
            },
            [
              for (var page in unordered)
                _buildUnorderedPageTile(page),
            ],
          ),
        ],
      ],
    );
  }

  Component _buildOrderedPageRow(FanzinePage page, int index, List<FanzinePage> ordered) {
    final num = page.pageNumber;
    final bool isFirstPage = num == 1;
    final bool showLayoutButtons = !(isFirstPage && component.fanzine.hasCover);
    final String? thumbUrl = page.gridUrl ?? page.imageUrl;

    return div(
      attributes: const {
        'style': 'display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; background-color: white; border: 1px solid #eee; border-radius: 8px; box-sizing: border-box; width: 100%; gap: 12px; flex-wrap: wrap;'
      },
      [
        // Page Number & Thumbnail & Label
        div(
          attributes: const {'style': 'display: flex; align-items: center; gap: 10px; min-width: 140px;'},
          [
            span(
              [Component.text('$num.')],
              attributes: const {'style': 'font-weight: bold; font-size: 12px; width: 24px; color: black;'},
            ),
            div(
              attributes: {
                'style': 'width: 32px; height: 48px; background-color: #f0f0f0; border-radius: 4px; border: 1px solid #ddd; overflow: hidden; display: flex; align-items: center; justify-content: center;'
              },
              [
                if (thumbUrl != null && thumbUrl.isNotEmpty)
                  img(src: thumbUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
                else
                  span([Component.text('auto_awesome_motion')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px; color: #aaa;'}),
              ],
            ),
            span(
              [Component.text(page.templateId != null ? 'template page' : 'image page')],
              attributes: const {'style': 'font-size: 11px; color: #555;'},
            ),
          ],
        ),

        if (showLayoutButtons)
          div(
            attributes: const {'style': 'display: flex; align-items: center; gap: 8px; flex-wrap: wrap;'},
            [
              // Spread Position Segment (start / end)
              div(
                attributes: const {'style': 'display: flex; border: 1px solid #ccc; border-radius: 14px; overflow: hidden; background: white;'},
                [
                  _buildSegmentItem('start', page.spreadPosition == 'start', () {
                    final newVal = page.spreadPosition == 'start' ? null : 'start';
                    component.bloc.add(UpdatePageLayoutRequested(page, newVal, page.sidePreference, component.pages));
                  }),
                  _buildSegmentItem('end', page.spreadPosition == 'end', () {
                    final newVal = page.spreadPosition == 'end' ? null : 'end';
                    component.bloc.add(UpdatePageLayoutRequested(page, newVal, page.sidePreference, component.pages));
                  }),
                ],
              ),
              // Side Preference Segment (left / either / right)
              div(
                attributes: const {'style': 'display: flex; border: 1px solid #ccc; border-radius: 14px; overflow: hidden; background: white;'},
                [
                  _buildSegmentItem('left', page.sidePreference == 'left', () {
                    component.bloc.add(UpdatePageLayoutRequested(page, page.spreadPosition, 'left', component.pages));
                  }),
                  _buildSegmentItem('either', page.sidePreference == 'either' || page.sidePreference.isEmpty, () {
                    component.bloc.add(UpdatePageLayoutRequested(page, page.spreadPosition, 'either', component.pages));
                  }),
                  _buildSegmentItem('right', page.sidePreference == 'right', () {
                    component.bloc.add(UpdatePageLayoutRequested(page, page.spreadPosition, 'right', component.pages));
                  }),
                ],
              ),
            ],
          ),

        div(
          attributes: const {'style': 'display: flex; align-items: center; gap: 8px; margin-left: auto;'},
          [
            if (isFirstPage)
              div(
                attributes: const {'style': 'display: flex; align-items: center; gap: 6px; margin-right: 8px;'},
                [
                  span([Component.text('cover')], attributes: const {'style': 'font-size: 10px; color: #666;'}),
                  input(
                    type: InputType.checkbox,
                    attributes: {
                      'style': 'cursor: pointer; width: 14px; height: 14px;',
                      if (component.fanzine.hasCover) 'checked': 'true',
                    },
                    events: {
                      'change': (e) {
                        component.bloc.add(ToggleHasCoverRequested(!component.fanzine.hasCover));
                      }
                    },
                  ),
                ],
              ),
            button(
              [span([Component.text('arrow_upward')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
              attributes: {
                'type': 'button',
                'title': 'move up',
                'style': 'border: none; background: transparent; cursor: ${num > 1 ? "pointer" : "default"}; color: ${num > 1 ? "#333" : "#ccc"}; padding: 4px;'
              },
              events: {
                'click': (e) {
                  if (num > 1) {
                    component.bloc.add(ReorderPageRequested(page, -1, component.pages));
                  }
                }
              },
            ),
            button(
              [span([Component.text('arrow_downward')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
              attributes: {
                'type': 'button',
                'title': 'move down',
                'style': 'border: none; background: transparent; cursor: ${num < ordered.length ? "pointer" : "default"}; color: ${num < ordered.length ? "#333" : "#ccc"}; padding: 4px;'
              },
              events: {
                'click': (e) {
                  if (num < ordered.length) {
                    component.bloc.add(ReorderPageRequested(page, 1, component.pages));
                  }
                }
              },
            ),
            button(
              [span([Component.text('close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})],
              attributes: const {
                'type': 'button',
                'title': 'unorder page',
                'style': 'border: none; background: transparent; cursor: pointer; color: #ef4444; padding: 4px;'
              },
              events: {
                'click': (e) {
                  component.bloc.add(TogglePageOrderingRequested(page, false));
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Component _buildUnorderedPageTile(FanzinePage page) {
    final String? thumbUrl = page.gridUrl ?? page.imageUrl;

    return div(
      attributes: const {
        'style': 'aspect-ratio: 5 / 8; background-color: #f5f5f5; border: 1px dashed #ccc; border-radius: 6px; position: relative; overflow: hidden; cursor: pointer; display: flex; align-items: center; justify-content: center;'
      },
      events: {
        'click': (e) {
          component.bloc.add(TogglePageOrderingRequested(page, true));
        }
      },
      [
        if (thumbUrl != null && thumbUrl.isNotEmpty)
          img(src: thumbUrl, attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'})
        else
          span([Component.text('auto_awesome_motion')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 24px; color: #aaa;'}),
        div(
          [Component.text('+ add')],
          attributes: const {
            'style': 'position: absolute; bottom: 4px; background: rgba(0,0,0,0.65); color: white; font-size: 9px; font-weight: bold; padding: 2px 6px; border-radius: 4px;'
          },
        ),
      ],
    );
  }

  Component _buildSegmentItem(String label, bool isSelected, void Function() onTap) {
    return button(
      [Component.text(label)],
      attributes: {
        'type': 'button',
        'style': 'border: none; padding: 4px 8px; font-size: 9px; font-weight: bold; cursor: pointer; '
            'background-color: ${isSelected ? "#8e8e8e" : "transparent"}; '
            'color: ${isSelected ? "white" : "#444"};'
      },
      events: {'click': (e) => onTap()},
    );
  }
}