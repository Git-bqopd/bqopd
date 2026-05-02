/// The entrypoint for the **server** environment.
///
/// The [main] method will only be executed on the server during pre-rendering.
/// To run code on the client, check the `main.client.dart` file.
library;

import 'package:jaspr/server.dart';

// Imports the [App] component.
import 'app.dart';
// Import the centralized theme styles
import 'constants/theme.dart' as theme;

// This file is generated automatically by Jaspr, do not remove or edit.
// Note: This file will appear after the first successful 'jaspr serve' build.
import 'main.server.options.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultServerOptions,
  );

  // Starts the app.
  //
  // [Document] renders the root document structure (<html>, <head> and <body>)
  // with the provided parameters and components.
  runApp(Document(
    title: 'bqopd',
    // We use the centralized styles from theme.dart
    styles: theme.styles,
    body: const App(),
  ));
}