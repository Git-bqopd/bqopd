import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import 'reader_page_item.dart';

class FanzineListRenderer extends StatelessComponent {
  final String fanzineId;
  final List<Map<String, dynamic>> pages;
  final Component headerWidget;
  final VoidCallback? onOpenGrid;
  final BonusRowType? activeGlobalPanel; // Added to fix undefined parameter error
  final ValueChanged<BonusRowType>? onTogglePanel; // Added to fix undefined parameter error

  const FanzineListRenderer({
    required this.fanzineId,
    required this.pages,
    required this.headerWidget,
    this.onOpenGrid,
    this.activeGlobalPanel,
    this.onTogglePanel,
  });

  @override
  Component build(BuildContext context) {
    return div(classes: 'flex-col items-center w-full', [
      // Wrap the header in the Manila Envelope so it looks correct in List View
      div(classes: 'mb-4 flex justify-center w-full', [
        div(classes: 'manila-envelope', [headerWidget])
      ]),

      for (int i = 0; i < pages.length; i++)
        ReaderPageItem(
          fanzineId: fanzineId,
          pageData: pages[i],
          pageIndex: i,
          onOpenGrid: onOpenGrid,
        )
    ]);
  }
}