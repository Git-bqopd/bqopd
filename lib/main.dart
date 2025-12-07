import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';

// Pages
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/fanzine_page.dart';
import 'pages/profile_page.dart';
import 'pages/short_link_page.dart';
import 'pages/edit_info_page.dart';
import 'pages/settings_page.dart';
import 'pages/fanzine_editor_page.dart';

// --- helper to refresh router when auth state changes ---
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  usePathUrlStrategy(); // pretty web URLs (no #)
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/',
      refreshListenable:
      GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),

      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;
        final path = state.fullPath ?? '/';

        // Pages that REQUIRE login.
        // If a user tries to go here while logged out, send them to login.
        final isProtected = path == '/profile' ||
            path == '/settings' ||
            path == '/edit-info' ||
            path.startsWith('/editor');

        if (user == null && isProtected) {
          return '/login';
        }

        // If user is logged in and tries to access explicit login/register,
        // send them to home (/).
        if (user != null && (path == '/login' || path == '/register')) {
          return '/';
        }

        // Otherwise, no redirection needed.
        // The "/" route (FanzinePage) handles both Auth and Unauth states internally.
        return null;
      },

      routes: [
        // ROOT: The main "Landing Page" / "Dashboard"
        GoRoute(
          path: '/',
          name: 'root',
          builder: (context, state) => const FanzinePage(),
        ),

        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/register',
          name: 'register',
          builder: (context, state) => const RegisterPage(),
        ),

        // This acts as the Private Dashboard route explicitly if needed
        GoRoute(
          path: '/fanzine',
          name: 'fanzine',
          builder: (context, state) => const FanzinePage(),
        ),

        // Private Profile Routes
        GoRoute(
          path: '/profile',
          name: 'profile',
          builder: (context, state) => const ProfilePage(),
        ),
        GoRoute(
          path: '/edit-info',
          name: 'editInfo',
          builder: (context, state) => const EditInfoPage(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: '/editor/:fanzineId',
          name: 'fanzineEditor',
          builder: (context, state) {
            final fanzineId = state.pathParameters['fanzineId']!;
            return FanzineEditorPage(fanzineId: fanzineId);
          },
        ),

        // PUBLIC: /:code (The "Traffic Cop" Route for Vanity URLs)
        GoRoute(
          path: '/:code',
          name: 'shortlink',
          builder: (context, state) {
            final code = state.pathParameters['code']!;
            return ShortLinkPage(code: code);
          },
        ),
      ],
      errorBuilder: (context, state) =>
      const Scaffold(body: Center(child: Text('Page not found'))),
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'bqopd',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerConfig: router,
    );
  }
}