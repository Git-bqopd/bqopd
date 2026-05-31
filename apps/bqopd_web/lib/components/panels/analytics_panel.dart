import 'package:jaspr/jaspr.dart';
import '../stats_table.dart';

/// Analytics Panel wrapping the lightweight StatsTable component.
class AnalyticsPanel extends StatelessComponent {
  final String imageId;
  const AnalyticsPanel({required this.imageId, super.key});

  @override
  Component build(BuildContext context) {
    return StatsTable(
      contentId: imageId,
      isFanzine: false,
    );
  }
}