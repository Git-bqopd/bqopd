import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'fanzine_spread_tile.dart';

class GridSpread {
  Component? leftWidget;
  Map<String, dynamic>? leftPage;
  Map<String, dynamic>? rightPage;
  int? leftListIndex;
  int? rightListIndex;

  GridSpread({this.leftWidget, this.leftListIndex});
}

class FanzineGridRenderer extends StatelessComponent {
  final List<Map<String, dynamic>> pages;
  final Component headerWidget;
  final bool hasCover;
  final Function(int) onPageTap;

  const FanzineGridRenderer({
    required this.pages,
    required this.headerWidget,
    this.hasCover = true,
    required this.onPageTap,
  });

  @override
  Component build(BuildContext context) {
    List<GridSpread> spreads = [];
    GridSpread currentSpread = GridSpread(
      leftWidget: headerWidget,
      leftListIndex: 0,
    );

    int pageIndex = 0;
    bool nextIsLeft = false;

    if (hasCover && pages.isNotEmpty) {
      currentSpread.rightPage = pages[0];
      currentSpread.rightListIndex = 1;
      pageIndex = 1;
      spreads.add(currentSpread);
      currentSpread = GridSpread();
      nextIsLeft = true;
    } else {
      spreads.add(currentSpread);
      currentSpread = GridSpread();
      nextIsLeft = true;
    }

    while (pageIndex < pages.length) {
      final page = pages[pageIndex];
      final String pref = page['sidePreference'] ?? 'either';

      if (nextIsLeft) {
        if (pref == 'right') {
          currentSpread.rightPage = page;
          currentSpread.rightListIndex = pageIndex + 1;
          spreads.add(currentSpread);
          currentSpread = GridSpread();
          nextIsLeft = true;
        } else {
          currentSpread.leftPage = page;
          currentSpread.leftListIndex = pageIndex + 1;
          nextIsLeft = false;
        }
      } else {
        if (pref == 'left') {
          spreads.add(currentSpread);
          currentSpread = GridSpread();
          currentSpread.leftPage = page;
          currentSpread.leftListIndex = pageIndex + 1;
          nextIsLeft = false;
        } else {
          currentSpread.rightPage = page;
          currentSpread.rightListIndex = pageIndex + 1;
          spreads.add(currentSpread);
          currentSpread = GridSpread();
          nextIsLeft = true;
        }
      }
      pageIndex++;
    }

    if (!nextIsLeft) {
      spreads.add(currentSpread);
    }

    return div(classes: 'flex-col items-center w-full pb-8', [
      for (var spread in spreads)
        FanzineSpreadTile(
          leftWidget: spread.leftWidget,
          leftPageData: spread.leftPage,
          rightPageData: spread.rightPage,
          leftIndex: spread.leftListIndex,
          rightIndex: spread.rightListIndex,
          onPageTap: onPageTap,
        )
    ]);
  }
}