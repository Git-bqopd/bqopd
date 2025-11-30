import 'dart:async';
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
        // fullPath might be null on startup, default to root
        final path = state.fullPath ?? '/';

        // 1. Identify the type of route we are on
        final isLoggingIn = path == '/login' || path == '/register';
        final isRoot = path == '/';
        final isProtected = path == '/fanzine' || path == '/profile';

        // 2. Logic for Unauthenticated Users
        if (user == null) {
          // If trying to go to Root OR a Protected route, force Login
          if (isRoot || isProtected) {
            return '/login';
          }
          // Allow access to Login, Register, and Shortlinks (/:code)
          return null;
        }

        // 3. Logic for Authenticated Users
        if (user != null) {
          // If trying to go to Root, Login, or Register, send to Home (Fanzine)
          if (isRoot || isLoggingIn) {
            return '/fanzine';
          }
          // Allow access to Profile, Fanzine, and Shortlinks
          return null;
        }

        return null;
      },

      routes: [
        GoRoute(
          path: '/',
          name: 'root',
          // This builder is only seen briefly while the redirect logic decides where to go
          builder: (context, state) => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
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
        GoRoute(
          path: '/fanzine',
          name: 'fanzine',
          builder: (context, state) => const FanzinePage(),
        ),
        GoRoute(
          path: '/profile',
          name: 'profile',
          builder: (context, state) => const ProfilePage(),
        ),

        // PUBLIC: /:code (either a fanzine shortcode or a username)
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