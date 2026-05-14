import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

class FanzineSpreadTile extends StatelessComponent {
  final Component? leftWidget;
  final Map<String, dynamic>? leftPageData;
  final Map<String, dynamic>? rightPageData;
  final int? leftIndex;
  final int? rightIndex;
  final Function(int) onPageTap;

  const FanzineSpreadTile({
    this.leftWidget,
    this.leftPageData,
    this.rightPageData,
    this.leftIndex,
    this.rightIndex,
    required this.onPageTap,
  });

  @override
  Component build(BuildContext context) {
    final bool isHeaderRow = leftWidget != null;

    // The base spread is the white paper in the background
    final baseSpread = div(
        classes: 'spread-paper',
        [
          // Left Page Container
          div(classes: 'spread-half left', [
            if (leftPageData != null) _buildPageItem(leftPageData!, leftIndex!)
          ]),
          // Right Page Container
          div(classes: 'spread-half right', [
            if (rightPageData != null) _buildPageItem(rightPageData!, rightIndex!)
          ])
        ]
    );

    // We wrap everything in the AspectRatio bounded box
    return div(
        classes: 'spread-wrapper',
        [
          // 1. The standard paper spread
          baseSpread,

          // 2. Overlay Manila Envelope if this is the header row
          if (isHeaderRow)
            div(classes: 'header-envelope-overlay', [
              div(classes: 'manila-envelope-cover', [
                leftWidget!
              ])
            ])
        ]
    );
  }

  Component _buildPageItem(Map<String, dynamic> pageData, int index) {
    // Prioritize 450px gridUrl, then fall back to fileUrl
    final String? url = pageData['gridUrl'] ?? pageData['thumbnailUrl'] ?? pageData['imageUrl'];
    final pageNum = pageData['pageNumber'] ?? index;

    return div(
        classes: 'page-wrapper-border cursor-pointer',
        events: {'click': (e) => onPageTap(index)},
        [
          if (url != null && url.isNotEmpty)
            img(src: url)
          else
            p(classes: 'text-gray text-xs', [text('Page $pageNum')])
        ]
    );
  }
}