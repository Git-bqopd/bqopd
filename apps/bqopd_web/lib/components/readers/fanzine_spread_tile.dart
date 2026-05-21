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

    final baseSpread = div(
        classes: 'spread-paper',
        [
          div(classes: 'spread-half left', [
            if (leftPageData != null) _buildPageItem(leftPageData!, leftIndex!)
          ]),
          div(classes: 'spread-half right', [
            if (rightPageData != null) _buildPageItem(rightPageData!, rightIndex!)
          ])
        ]
    );

    return div(
        classes: 'spread-wrapper',
        [
          baseSpread,

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
    final String? url = pageData['gridUrl'] ?? pageData['thumbnailUrl'] ?? pageData['imageUrl'];
    final pageNum = pageData['pageNumber'] ?? index;

    return div(
        classes: 'page-wrapper-border cursor-pointer',
        events: {'click': (e) => onPageTap(index)},
        [
          if (url != null && url.isNotEmpty)
            img(
              src: url,
              attributes: {
                'loading': 'lazy', // HIGH-PERFORMANCE: Offscreen images won't compete with main JS file
                'alt': 'Page $pageNum',
              },
            )
          else
            p(classes: 'text-gray text-xs', [text('Page $pageNum')])
        ]
    );
  }
}