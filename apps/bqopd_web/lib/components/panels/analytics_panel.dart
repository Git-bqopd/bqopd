import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../stats_table.dart';

/// Dedicated inline drawer (bonusRow) analytics panel for a single page image.
class AnalyticsRowPanel extends StatelessComponent {
  final String imageId;
  const AnalyticsRowPanel({required this.imageId, super.key});

  @override
  Component build(BuildContext context) {
    return StatsTable(
      contentId: imageId,
      isFanzine: false,
    );
  }
}

/// Dedicated desktop 3rd column (bonusColumn) analytics panel.
/// Can show entire fanzine issue statistics or a dedicated inspection widget.
class AnalyticsColumnPanel extends StatelessComponent {
  final String? fanzineId;
  final String imageId;
  final List<Map<String, dynamic>> pages;
  final Map<String, Map<String, dynamic>> preloadedStats;

  const AnalyticsColumnPanel({
    this.fanzineId,
    required this.imageId,
    this.pages = const [],
    this.preloadedStats = const {},
    super.key,
  });

  @override
  Component build(BuildContext context) {
    if (fanzineId != null && fanzineId!.isNotEmpty) {
      return div(
          [
            div([
              span([Component.text('ISSUE ANALYTICS OVERVIEW')], attributes: const {
                'style': 'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;'
              }),
            ], attributes: const {'style': 'margin-bottom: 12px;'}),
            StatsTable(
              contentId: fanzineId!,
              isFanzine: true,
              preloadedPages: pages,
              preloadedStats: preloadedStats,
            )
          ],
          classes: 'w-full p-2'
      );
    }
    return StatsTable(
      contentId: imageId,
      isFanzine: false,
    );
  }
}

/// Backwards-compatible alias
typedef AnalyticsPanel = AnalyticsRowPanel;