// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:jaspr_app/constants/theme.dart' as _theme;
import 'package:jaspr_app/pages/about.dart' as _about;
import 'package:jaspr_app/pages/home.dart' as _home;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _about.AboutPage: ClientTarget<_about.AboutPage>('about'),
    _home.HomePage: ClientTarget<_home.HomePage>('home'),
  },
  styles: () => [..._theme.styles],
);
