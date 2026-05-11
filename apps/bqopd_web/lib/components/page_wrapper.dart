import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Replicates the structural aesthetics of the Flutter PageWrapper,
/// wrapping content in the Manila Envelope and White Sticker HTML nodes.
class PageWrapper extends StatelessComponent {
  final Component child;

  const PageWrapper({required this.child});

  @override
  Component build(BuildContext context) {
    return div(classes: 'manila-envelope', [
      div(classes: 'white-sticker', [
        child
      ])
    ]);
  }
}