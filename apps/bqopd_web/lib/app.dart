import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Component build(BuildContext context) {
    return div(classes: 'app-container', [
      h1([text('bqopd Jaspr Web App')]),
      p([text('System Stable. UI Rendering successfully!')]),

      div(classes: 'core-test', [
        h3([text('Architecture Note:')]),
        p([text('Firebase and BLoCs are temporarily disconnected from Jaspr to prevent Flutter plugin crashes.')]),
        p([text('In the next session, we will fix this by creating abstract Repository interfaces so pure Dart and Flutter can safely share the BLoCs.')]),
      ])
    ]);
  }
}