import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';

class PanelContainer extends StatelessComponent {
  final String title;
  final BonusRowType type;
  final Component child;

  const PanelContainer({
    required this.title,
    required this.type,
    required this.child,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    // Apply background tints to differentiate interaction rows
    String bgColor = '#ffffff';
    if (type == BonusRowType.textReader) bgColor = '#FDFBF7';
    if (type == BonusRowType.comments) bgColor = '#ffffff';

    // Text editors and readers should grow dynamically to arbitrary lengths without any transition-induced clipping.
    // For these panels, we omit 'panel-container-animate' to bypass CSS max-height caps completely.
    final bool isUnlimitedHeight = type == BonusRowType.textReader ||
        type == BonusRowType.masterText ||
        type == BonusRowType.linkedText;

    final String classesStr = isUnlimitedHeight
        ? 'p-4 mt-2'
        : 'p-4 mt-2 panel-container-animate';

    return div(
        classes: classesStr,
        attributes: {
          'style': 'background-color: $bgColor; border-top: 1px solid #eee; border-bottom: 1px solid #eee; overflow: visible;'
        },
        [
          div(classes: 'flex-col', [
            if (title.isNotEmpty)
              div(classes: 'mb-2', [
                span(
                    classes: 'text-xs font-bold text-gray',
                    attributes: {'style': 'letter-spacing: 1px; text-transform: uppercase;'},
                    [text(title)]
                )
              ]),
            child
          ])
        ]
    );
  }
}