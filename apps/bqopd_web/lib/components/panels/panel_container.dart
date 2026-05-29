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

    // Added panel-container-animate rule for hardware-accelerated entry transitions
    return div(
        classes: 'p-4 mt-2 panel-container-animate',
        attributes: {
          'style': 'background-color: $bgColor; border-top: 1px solid #eee; border-bottom: 1px solid #eee;'
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