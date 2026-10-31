import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Renders the 72-page (3 × 24p) Micro-Spread Flatplan Board in the Week Dashboard.
class MicroSpreadBoard extends StatelessComponent {
  final List<BundlePageDef> zine1;
  final List<BundlePageDef> zine2;
  final List<BundlePageDef> zine3;
  final List<ScheduledFanzine> activeFanzines;
  final String? activeBlueprintId;
  final String? activeCategoryFilter;
  final void Function(String category) onToggleCategoryFilter;
  final void Function(ScheduledFanzine fanzine, int slotIndex)? onSelectFanzine;

  const MicroSpreadBoard({
    required this.zine1,
    required this.zine2,
    required this.zine3,
    required this.activeFanzines,
    required this.activeBlueprintId,
    required this.activeCategoryFilter,
    required this.onToggleCategoryFilter,
    this.onSelectFanzine,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    final sub1 = activeFanzines.isNotEmpty ? activeFanzines[0].title : 'Radius';
    final sub2 = activeFanzines.length > 1 ? activeFanzines[1].title : 'Articles';
    final sub3 = activeFanzines.length > 2 ? activeFanzines[2].title : 'Community';

    return div(
      attributes: const {
        'style':
            'background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 12px; '
                'display: flex; flex-direction: column; align-items: center; width: 284px; flex-shrink: 0; box-sizing: border-box; '
                'box-shadow: 0 1px 3px rgba(0,0,0,0.03);',
      },
      [
        div(
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center; width: 100%; '
                    'border-bottom: 1px solid #e2e8f0; padding-bottom: 6px; margin-bottom: 8px;',
          },
          [
            span(
              [Component.text('72-PAGE BUNDLE')],
              attributes: const {
                'style':
                    'font-size: 10px; font-weight: 900; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;',
              },
            ),
            span(
              [Component.text('${activeFanzines.length} / 3 Zines')],
              attributes: {
                'style':
                    'font-size: 9px; font-weight: bold; '
                        'color: ${activeFanzines.length == 3 ? "#16a34a" : "#ca8a04"}; '
                        'background: ${activeFanzines.length == 3 ? "#ecfdf5" : "#fefce8"}; '
                        'border: 1px solid ${activeFanzines.length == 3 ? "#bbf7d0" : "#fef08a"}; '
                        'border-radius: 4px; padding: 1px 5px;',
              },
            ),
          ],
        ),
        div(
          attributes: const {
            'style': 'display: flex; gap: 10px; justify-content: center; width: 100%;',
          },
          [
            _buildZineColumn(
              1,
              sub1,
              '#10B981',
              zine1,
              activeFanzines.isNotEmpty ? activeFanzines[0] : null,
            ),
            _buildZineColumn(
              2,
              sub2,
              '#3B82F6',
              zine2,
              activeFanzines.length > 1 ? activeFanzines[1] : null,
            ),
            _buildZineColumn(
              3,
              sub3,
              '#F59E0B',
              zine3,
              activeFanzines.length > 2 ? activeFanzines[2] : null,
            ),
          ],
        ),
      ],
    );
  }

  Component _buildZineColumn(
    int zineNum,
    String subtitle,
    String subtitleColor,
    List<BundlePageDef> pages,
    ScheduledFanzine? fanzine,
  ) {
    final bool isSelectedBlueprint =
        fanzine != null && fanzine.id == activeBlueprintId;

    return div(
      attributes: {
        'style':
            'width: 80px; min-width: 80px; max-width: 80px; display: flex; flex-direction: column; '
                'gap: 3px; align-items: center; box-sizing: border-box; '
                '${isSelectedBlueprint ? "background: #f3f0fb; border-radius: 4px; padding: 2px;" : ""}',
      },
      [
        // Column Header (clickable to preview that Zine's blueprint in Columns 1 & 2)
        div(
          attributes: {
            'style':
                'width: 100%; text-align: center; border-bottom: 1px solid ${isSelectedBlueprint ? "#6750A4" : "#e2e8f0"}; '
                    'padding-bottom: 3px; margin-bottom: 2px; overflow: hidden; '
                    '${fanzine != null ? "cursor: pointer;" : ""}',
            if (fanzine != null)
              'title': 'Click to preview ${fanzine.title} in Columns 1 & 2',
          },
          events: {
            if (fanzine != null && onSelectFanzine != null)
              'click': (e) => onSelectFanzine!(fanzine, zineNum),
          },
          [
            span(
              [Component.text('ZINE #$zineNum')],
              attributes: {
                'style':
                    'font-family: Anton, sans-serif; font-size: 11px; letter-spacing: 0.5px; '
                        'color: ${isSelectedBlueprint ? "#6750A4" : "#0f172a"}; display: block; line-height: 1;',
              },
            ),
            span(
              [Component.text(subtitle)],
              attributes: {
                'title': subtitle,
                'style':
                    'font-size: 9px; font-weight: bold; color: $subtitleColor; display: block; margin-top: 2px; '
                        'white-space: nowrap; overflow: hidden; text-overflow: ellipsis;',
              },
            ),
          ],
        ),

        // SPREAD 1 (Front Cover Spread): Blank space on Left, Page 1 on Right
        div(
          attributes: const {
            'style':
                'width: 100%; display: flex; gap: 2px; background: rgba(226, 232, 240, 0.6); '
                    'padding: 2px; border-radius: 2px; box-sizing: border-box;',
          },
          [
            _buildBlankPageBox(),
            _buildMicroPageBox(pages[0]),
          ],
        ),

        // SPREADS 2..12 (Interior Facing Spreads): Pages 2 through 23
        for (int s = 1; s <= 11; s++)
          div(
            attributes: const {
              'style':
                  'width: 100%; display: flex; gap: 2px; background: rgba(226, 232, 240, 0.6); '
                      'padding: 2px; border-radius: 2px; box-sizing: border-box;',
            },
            [
              _buildMicroPageBox(pages[(s - 1) * 2 + 1]),
              _buildMicroPageBox(pages[(s - 1) * 2 + 2]),
            ],
          ),

        // SPREAD 13 (Back Cover Spread): Page 24 on Left, Blank space on Right
        div(
          attributes: const {
            'style':
                'width: 100%; display: flex; gap: 2px; background: rgba(226, 232, 240, 0.6); '
                    'padding: 2px; border-radius: 2px; box-sizing: border-box;',
          },
          [
            _buildMicroPageBox(pages[23]),
            _buildBlankPageBox(),
          ],
        ),
      ],
    );
  }

  Component _buildBlankPageBox() {
    return div(
      attributes: const {
        'style':
            'flex: 1; aspect-ratio: 5 / 8; background-color: #ffffff; border: 1px dashed #cbd5e1; '
                'border-radius: 1px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; '
                'user-select: none; pointer-events: none;',
      },
      [],
    );
  }

  Component _buildMicroPageBox(BundlePageDef page) {
    final bool isFiltered = activeCategoryFilter != null;
    final bool matchesFilter = page.category == activeCategoryFilter;

    final color = publisherCategoryColors[page.category] ?? '#6750A4';
    final double opacity = (isFiltered && !matchesFilter) ? 0.2 : 1.0;
    final String outline = matchesFilter ? '2px solid #000000' : 'none';

    return div(
      attributes: {
        'title':
            'Zine #${page.zineNum} · Page ${page.pageNum} (${page.category.toUpperCase()} — ${page.label})',
        'style':
            'flex: 1; aspect-ratio: 5 / 8; background-color: $color; border-radius: 1px; '
                'display: flex; align-items: center; justify-content: center; user-select: none; '
                'font-size: 8px; font-weight: bold; font-family: monospace; color: rgba(255, 255, 255, 0.95); '
                'opacity: $opacity; outline: $outline; outline-offset: 1px; cursor: pointer; '
                'transition: transform 0.1s ease, opacity 0.15s ease;',
      },
      events: {
        'click': (e) => onToggleCategoryFilter(page.category),
      },
      [Component.text('${page.pageNum}')],
    );
  }
}
