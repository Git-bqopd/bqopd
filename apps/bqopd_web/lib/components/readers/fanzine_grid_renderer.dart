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

/// Calculates the exact zero-based spread index containing the given [listIndex].
/// [listIndex] of 0 corresponds to the header envelope, and 1..N correspond to page items.
int getSpreadIndexForListIndex({
  required int listIndex,
  required List<Map<String, dynamic>> pages,
  required bool hasCover,
}) {
  if (listIndex <= 0) return 0;
  if (hasCover && listIndex == 1) return 0;

  int currentSpread = 0;
  int pageIndex = 0;
  bool nextIsLeft = false;

  if (hasCover && pages.isNotEmpty) {
    pageIndex = 1;
    currentSpread++;
    nextIsLeft = true;
  } else {
    currentSpread++;
    nextIsLeft = true;
  }

  while (pageIndex < pages.length) {
    final int currentListIndex = pageIndex + 1;
    final page = pages[pageIndex];
    final String pref = page['sidePreference'] ?? 'either';

    if (nextIsLeft) {
      if (pref == 'right') {
        if (currentListIndex == listIndex) return currentSpread;
        currentSpread++;
        nextIsLeft = true;
      } else {
        if (currentListIndex == listIndex) return currentSpread;
        nextIsLeft = false;
      }
    } else {
      if (pref == 'left') {
        currentSpread++;
        if (currentListIndex == listIndex) return currentSpread;
        nextIsLeft = false;
      } else {
        if (currentListIndex == listIndex) return currentSpread;
        currentSpread++;
        nextIsLeft = true;
      }
    }
    pageIndex++;
  }

  return currentSpread;
}

/// Grid renderer for Column 1 (`#fanzine-grid-area`).
/// Mounts the persistent pinned [stickyHeaderWidget] at the very top of the scroll container,
/// followed by all two-page publication spreads scrolling underneath.
class FanzineGridRenderer extends StatelessComponent {
  final List<Map<String, dynamic>> pages;
  final Component headerWidget;
  final Component? stickyHeaderWidget;
  final bool hasCover;
  final Function(int) onPageTap;

  const FanzineGridRenderer({
    required this.pages,
    required this.headerWidget,
    this.stickyHeaderWidget,
    this.hasCover = true,
    required this.onPageTap,
    super.key,
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

    return div(
      classes: 'fanzine-grid-scroll-tree flex-col items-center w-full pb-8',
      attributes: const {
        'style': 'position: relative; width: 100%; box-sizing: border-box;'
      },
      [
        if (stickyHeaderWidget != null) stickyHeaderWidget!,
        for (int sIndex = 0; sIndex < spreads.length; sIndex++)
          FanzineSpreadTile(
            id: 'grid-spread-$sIndex',
            leftWidget: spreads[sIndex].leftWidget,
            leftPageData: spreads[sIndex].leftPage,
            rightPageData: spreads[sIndex].rightPage,
            leftIndex: spreads[sIndex].leftListIndex,
            rightIndex: spreads[sIndex].rightListIndex,
            onPageTap: onPageTap,
            key: ValueKey('grid_spread_$sIndex'),
          )
      ],
    );
  }
}