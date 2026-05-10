import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart'; // REQUIRED in 0.23.1+ for div, p, h1, text
import 'package:bqopd_core/bqopd_core.dart';

class App extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    // Generate test data from our core package utility
    final testWeeks = generateConWeeks("February", "2026");

    return div(classes: 'app-container', [
      h1([text('bqopd Jaspr Web App')]),
      p([text('Hello world! The Jaspr app is successfully running in the workspace.')]),

      div(classes: 'core-test', [
        h3([text('Core Package Test (con_week.dart):')]),
        p([text('First ConWeek: ${testWeeks.first.displayString}')]),
      ])
    ]);
  }
}