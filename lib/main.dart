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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;

        // Use uri.path to get the actual path (e.g. "/QrNsbYA")
        final path = state.uri.path;
        // Use fullPath to check against route patterns (e.g. "/editor/:fanzineId")
        final routePattern = state.fullPath;

        // Pages that REQUIRE login.
        final isProtected = path == '/profile' ||
            path == '/settings' ||
            path == '/edit-info' ||
            (routePattern != null && routePattern.startsWith('/editor'));

        // 1. If user is NOT logged in and tries to access a protected page -> Login
        if (user == null && isProtected) {
          return '/login';
        }

        // 2. If user IS logged in and tries to access explicit Login/Register -> Home
        if (user != null && (path == '/login' || path == '/register')) {
          return '/';
        }

        // 3. Otherwise, no redirection.
        // This ensures that vanity URLs (matched by /:code) remain in the browser bar.
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
        // This catches everything else, so it must be last.
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
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'bqopd',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerConfig: _router,
    );
  }
}