import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';

// existing pages
import 'auth/auth.dart';
import 'auth/login_or_register.dart';
import 'pages/fanzine_page.dart';
import 'pages/profile_page.dart';

// NEW: resolver page for /:code
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
        final loggingIn =
            state.fullPath == '/login' || state.fullPath == '/register';

        // Protected routes
        final needsAuth =
            state.fullPath == '/fanzine' || state.fullPath == '/profile';

        // Public short links like /QrNsbYA or /steve are always allowed
        final looksLikeShortLink = state.fullPath != null &&
            state.fullPath!.split('/').length == 2 &&
            state.fullPath!.split('/')[1].isNotEmpty;

        if (looksLikeShortLink) return null;

        if (!loggingIn && needsAuth && user == null) {
          return '/login';
        }
        if (loggingIn && user != null) {
          return '/fanzine';
        }
        return null;
      },

      routes: [
        GoRoute(
          path: '/',
          name: 'root',
          builder: (context, state) => const AuthPage(),
        ),
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => const LoginOrRegister(),
        ),
        GoRoute(
          path: '/register',
          name: 'register',
          builder: (context, state) => const LoginOrRegister(),
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
