import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'utils/script_loader.dart';
import 'env.dart'; // Import Env

// Pages
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/fanzine_page.dart';
import 'pages/profile_page.dart';
import 'pages/short_link_page.dart';
import 'pages/edit_info_page.dart';
import 'pages/settings_page.dart';
import 'pages/fanzine_editor_page.dart';

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

  // 1. Load Configuration from JSON
  await Env.load();

  // 2. Load the Web Script dynamically using the loaded Key
  await loadGoogleMapsScript();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  usePathUrlStrategy();
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
        final path = state.uri.path;
        final routePattern = state.fullPath;

        final isProtected = path == '/profile' ||
            path == '/settings' ||
            path == '/edit-info' ||
            (routePattern != null && routePattern.startsWith('/editor'));

        if (user == null && isProtected) return '/login';
        if (user != null && (path == '/login' || path == '/register')) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/', name: 'root', builder: (context, state) => const FanzinePage()),
        GoRoute(path: '/login', name: 'login', builder: (context, state) => const LoginPage()),
        GoRoute(path: '/register', name: 'register', builder: (context, state) => const RegisterPage()),
        GoRoute(path: '/fanzine', name: 'fanzine', builder: (context, state) => const FanzinePage()),
        GoRoute(path: '/profile', name: 'profile', builder: (context, state) => const ProfilePage()),
        GoRoute(path: '/edit-info', name: 'editInfo', builder: (context, state) => const EditInfoPage()),
        GoRoute(path: '/settings', name: 'settings', builder: (context, state) => const SettingsPage()),
        GoRoute(path: '/editor/:fanzineId', name: 'fanzineEditor', builder: (context, state) {
          final fanzineId = state.pathParameters['fanzineId']!;
          return FanzineEditorPage(fanzineId: fanzineId);
        },
        ),
        GoRoute(path: '/:code', name: 'shortlink', builder: (context, state) {
          final code = state.pathParameters['code']!;
          return ShortLinkPage(code: code);
        },
        ),
      ],
      errorBuilder: (context, state) => const Scaffold(body: Center(child: Text('Page not found'))),
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