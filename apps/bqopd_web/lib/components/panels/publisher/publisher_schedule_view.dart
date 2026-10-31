import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Renders the 52-week production schedule list in Column 3 of `/publisher`.
class PublisherScheduleView extends StatelessComponent {
  final int selectedYear;
  final int? selectedWeekNumber;
  final List<PublishingWeek> weeks;
  final Map<String, List<CirculationRecipient>> circulationCache;
  final void Function(PublishingWeek week) onOpenWeekDashboard;
  final void Function(PublishingWeek week) onOpenCirculation;

  const PublisherScheduleView({
    required this.selectedYear,
    required this.selectedWeekNumber,
    required this.weeks,
    required this.circulationCache,
    required this.onOpenWeekDashboard,
    required this.onOpenCirculation,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'flex-col gap-3 w-full',
      attributes: const {
        'style':
            'display: flex; flex-direction: column; gap: 12px; width: 100%; box-sizing: border-box;',
      },
      [
        // Header Section
        div(
          classes: 'flex-row justify-between items-center pb-2 mb-2',
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #d1d5db; padding-bottom: 8px;',
          },
          [
            div([
              span(
                [Component.text('PRODUCTION SCHEDULE')],
                attributes: const {
                  'style':
                      'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.8px; text-transform: uppercase;',
                },
              ),
              span(
                [Component.text('weekly release desk')],
                attributes: const {
                  'style':
                      'font-size: 10px; color: #94a3b8; display: block; margin-top: 1px;',
                },
              ),
            ]),
            span(
              [Component.text('$selectedYear')],
              attributes: const {
                'style':
                    'font-size: 11px; font-weight: bold; color: #1e293b; background: #ffffff; border: 1px solid #cbd5e1; border-radius: 4px; padding: 2px 8px;',
              },
            ),
          ],
        ),

        // List of Weekly Cards
        for (final week in weeks) _buildWeekCard(week),
      ],
    );
  }

  Component _buildWeekCard(PublishingWeek week) {
    final bool isSelected = week.weekNumber == selectedWeekNumber;
    final cachedList = circulationCache[week.weekId];
    final int recipientCount = cachedList?.length ?? 0;

    return div(
      classes: 'publisher-week-card transition-all',
      attributes: {
        'style':
            'width: 100%; background-color: #ffffff; border: ${isSelected ? "2px solid #6750A4" : "1px solid #cbd5e1"}; '
                'border-radius: 8px; padding: 14px 16px; box-sizing: border-box; cursor: pointer; '
                'box-shadow: ${isSelected ? "0 4px 12px rgba(103, 80, 164, 0.15)" : "0 1px 3px rgba(0, 0, 0, 0.05)"}; '
                'transition: all 0.15s ease;',
      },
      events: {
        'click': (e) => onOpenWeekDashboard(week),
      },
      [
        // Top Row: Week Number and Status Badge
        div(
          classes: 'flex-row justify-between items-center mb-1',
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 6px;',
          },
          [
            span(
              [
                Component.text(
                  'WEEK ${week.weekNumber.toString().padLeft(2, '0')}',
                ),
              ],
              attributes: {
                'style':
                    'font-size: 13px; font-weight: 900; letter-spacing: 0.5px; color: ${isSelected ? "#6750A4" : "#1e293b"};',
              },
            ),
            buildPublisherWeekStatusBadge(week),
          ],
        ),

        div(
          classes: 'flex-row justify-between items-center mt-2 pt-2',
          attributes: const {
            'style':
                'display: flex; justify-content: space-between; align-items: center; margin-top: 8px; padding-top: 8px; border-top: 1px solid #f1f5f9;',
          },
          [
            // Starting Monday Date
            div(
              classes: 'flex-row items-center gap-1',
              attributes: const {
                'style': 'display: flex; align-items: center; gap: 4px;',
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {
                    'style': 'font-size: 13px; color: #64748b; line-height: 1;',
                  },
                  [Component.text('calendar_today')],
                ),
                span(
                  [Component.text(week.startDateString)],
                  attributes: const {
                    'style':
                        'font-size: 11px; color: #64748b; font-weight: 500;',
                  },
                ),
              ],
            ),

            // Circulation Management Button
            button(
              classes: 'circulation-btn',
              attributes: {
                'type': 'button',
                'style':
                    'padding: 4px 10px; font-size: 10px; font-weight: bold; '
                        'background: ${isSelected ? "#6750A4" : "#f1f5f9"}; '
                        'color: ${isSelected ? "white" : "#475569"}; '
                        'border: 1px solid ${isSelected ? "#6750A4" : "#cbd5e1"}; '
                        'border-radius: 12px; cursor: pointer; display: inline-flex; '
                        'align-items: center; gap: 4px; transition: all 0.15s ease;',
              },
              events: {
                'click': (dynamic e) {
                  try {
                    e.stopPropagation();
                  } catch (_) {}
                  onOpenCirculation(week);
                },
              },
              [
                span(
                  classes: 'material-symbols-outlined',
                  attributes: const {
                    'style': 'font-size: 13px; line-height: 1;',
                  },
                  [Component.text('group')],
                ),
                Component.text(
                  recipientCount > 0
                      ? 'circulation ($recipientCount)'
                      : 'circulation',
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Shared status badge builder for a [PublishingWeek].
Component buildPublisherWeekStatusBadge(PublishingWeek week) {
  if (week.isCurrent) {
    return span(
      [Component.text('current')],
      attributes: const {
        'style':
            'font-size: 9px; font-weight: bold; background-color: #ecfdf5; color: #16a34a; '
                'border: 1px solid #bbf7d0; border-radius: 4px; padding: 1px 6px; text-transform: uppercase;',
      },
    );
  }

  if (week.isPast) {
    final label = week.publishedCount > 0
        ? 'archived (${week.publishedCount})'
        : 'archived';
    return span(
      [Component.text(label)],
      attributes: const {
        'style':
            'font-size: 9px; font-weight: 500; background-color: #f1f5f9; color: #475569; '
                'border: 1px solid #cbd5e1; border-radius: 4px; padding: 1px 6px; text-transform: uppercase;',
      },
    );
  }

  return span(
    [Component.text('upcoming')],
    attributes: const {
      'style':
          'font-size: 9px; font-weight: 500; background-color: #f8fafc; color: #64748b; '
              'border: 1px solid #e2e8f0; border-radius: 4px; padding: 1px 6px; text-transform: uppercase;',
    },
  );
}
