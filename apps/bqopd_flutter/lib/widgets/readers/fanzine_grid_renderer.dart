import 'package:flutter/material.dart';
import '../../services/view_service.dart';
import 'fanzine_spread_tile.dart';

class _GridSpread {
  Widget? leftWidget;
  Map<String, dynamic>? leftPage;
  Map<String, dynamic>? rightPage;
  int? leftListIndex;
  int? rightListIndex;

  _GridSpread({
    this.leftWidget,
    this.leftListIndex,
  });
}

class FanzineGridRenderer extends StatefulWidget {
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ScrollController scrollController;
  final Function(int) onPageTap;
  final ViewService viewService;
  final bool hasCover;

  const FanzineGridRenderer({
    super.key,
    required this.pages,
    required this.headerWidget,
    required this.scrollController,
    required this.onPageTap,
    required this.viewService,
    this.hasCover = true,
  });

  @override
  State<FanzineGridRenderer> createState() => _FanzineGridRendererState();
}

class _FanzineGridRendererState extends State<FanzineGridRenderer> {
  final String _fanzineTitle = 'Gallery View';
  final String _fanzineId = 'grid_view';

  @override
  Widget build(BuildContext context) {
    // Calculate the physical layout of the grid before rendering
    List<_GridSpread> spreads = [];

    // Spread 0 always begins with the Header (Manila Envelope) on the Left
    _GridSpread currentSpread = _GridSpread(
      leftWidget: widget.headerWidget,
      leftListIndex: 0,
    );

    int pageIndex = 0;
    bool nextIsLeft = false; // We just filled the left slot with the header

    // Handle Page 1 Cover Rule
    if (widget.hasCover && widget.pages.isNotEmpty) {
      currentSpread.rightPage = widget.pages[0];
      currentSpread.rightListIndex = 1;
      pageIndex = 1;
      spreads.add(currentSpread);
      currentSpread = _GridSpread();
      nextIsLeft = true;
    } else {
      // No cover, so the right slot of Spread 0 is blank paper
      spreads.add(currentSpread);
      currentSpread = _GridSpread();
      nextIsLeft = true;
    }

    // Process the rest of the pages with physical layout logic
    while (pageIndex < widget.pages.length) {
      final page = widget.pages[pageIndex];
      final String pref = page['sidePreference'] as String? ?? 'either';

      if (nextIsLeft) {
        if (pref == 'right') {
          // The page MUST be on the right, but we are on the left slot.
          // Leave the left slot blank and put it on the right.
          currentSpread.rightPage = page;
          currentSpread.rightListIndex = pageIndex + 1;
          spreads.add(currentSpread);
          currentSpread = _GridSpread();
          nextIsLeft = true;
        } else {
          // Prefers 'left' or 'either', put it in the available left slot.
          currentSpread.leftPage = page;
          currentSpread.leftListIndex = pageIndex + 1;
          nextIsLeft = false;
        }
      } else {
        // Next available slot is on the Right
        if (pref == 'left') {
          // The page MUST be on the left, but we are on the right slot.
          // Close the current spread leaving the right slot blank, and start a new spread.
          spreads.add(currentSpread);
          currentSpread = _GridSpread();

          currentSpread.leftPage = page;
          currentSpread.leftListIndex = pageIndex + 1;
          nextIsLeft = false;
        } else {
          // Prefers 'right' or 'either', put it in the available right slot.
          currentSpread.rightPage = page;
          currentSpread.rightListIndex = pageIndex + 1;
          spreads.add(currentSpread);
          currentSpread = _GridSpread();
          nextIsLeft = true;
        }
      }
      pageIndex++;
    }

    // If the loop finished and we have a half-full spread, add it to the list
    if (!nextIsLeft) {
      spreads.add(currentSpread);
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(vertical: 24),
      itemCount: spreads.length,
      itemBuilder: (context, rowIndex) {
        final spread = spreads[rowIndex];

        return FanzineSpreadTile(
          leftWidget: spread.leftWidget,
          leftPageData: spread.leftPage,
          rightPageData: spread.rightPage,
          leftIndex: spread.leftListIndex,
          rightIndex: spread.rightListIndex,
          onPageTap: widget.onPageTap,
          viewService: widget.viewService,
          fanzineId: _fanzineId,
          fanzineTitle: _fanzineTitle,
        );
      },
    );
  }
}