import 'package:jaspr/server.dart';
import 'app.dart';

/// Server entrypoint for Jaspr static site generation (SSG) and pre-rendering.
/// This bootstraps the application and pre-renders the app using web/index.html as the base template.
void main() {
  Jaspr.initializeApp();
  runApp(Document(
    body: App(),
  ));
}