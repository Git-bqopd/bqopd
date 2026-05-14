import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../social_toolbar.dart';

class ReaderPageItem extends StatelessComponent {
  final String fanzineId;
  final Map<String, dynamic> pageData;
  final int pageIndex;
  final VoidCallback? onOpenGrid;

  const ReaderPageItem({
    required this.fanzineId,
    required this.pageData,
    required this.pageIndex,
    this.onOpenGrid,
  });

  @override
  Component build(BuildContext context) {
    final String imageId = pageData['imageId'] ?? '';
    final String? url = pageData['listUrl'] ?? pageData['imageUrl'];

    return div(classes: 'reader-list-item flex-col w-full', [
      div(classes: 'aspect-5-8 bg-gray-100 flex-col items-center justify-center', [
        if (url != null && url.isNotEmpty)
          img(src: url, classes: 'w-full h-full', attributes: {'style': 'object-fit: contain;'})
        else
          p(classes: 'text-gray text-xs', [text('Processing...')])
      ]),
      div(classes: 'bg-white', [
        SocialToolbar(
          imageId: imageId,
          fanzineId: fanzineId,
          onOpenGrid: onOpenGrid,
        )
      ])
    ]);
  }
}