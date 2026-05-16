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
    // Apply background colors based on panel type to match Flutter's getInlineColor
    String bgColor = '#ffffff';
    if (type == BonusRowType.textReader) bgColor = '#FDFBF7';

    return div(
        classes: 'p-4 mt-2',
        attributes: {
          'style': 'background-color: $bgColor; border-top: 1px solid #eee; border-bottom: 1px solid #eee;'
        },
        [
          div(classes: 'flex-col', [
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