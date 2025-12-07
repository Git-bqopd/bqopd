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

      redirect: (context, state) async {
        final user = FirebaseAuth.instance.currentUser;
        final path = state.fullPath ?? '/';

        final isLoggingIn = path == '/login' || path == '/register';
        final isRoot = path == '/';

        // Define pages that require login (Private Dashboards)
        // /fanzine is now a PUBLIC page, so it's removed from isProtected!
        final isProtected = path == '/profile' ||
            path == '/settings' ||
            path == '/edit-info' ||
            path.startsWith('/editor');

        // 1. Unauthenticated User Logic
        if (user == null) {
          // If trying to access protected pages, go to login
          if (isProtected) {
            return '/login';
          }
          // If trying to access root, redirect to fanzine page, which is now the public landing page.
          if (isRoot) {
            return '/fanzine';
          }
          // Allow access to /fanzine, /login, /register, and /:code
          return null;
        }

        // 2. Authenticated User Logic
        if (user != null) {
          // If logged in and at Root/Login/Register, send them to their Vanity URL (Home)
          if (isRoot || isLoggingIn) {
            try {
              // Lookup their username to construct the redirect URL
              final doc = await FirebaseFirestore.instance
                  .collection('Users')
                  .doc(user.uid)
                  .get();

              if (doc.exists) {
                final data = doc.data();
                // Prefer username as the vanity URL if available
                final username = data?['username'] as String?;

                if (username != null && username.isNotEmpty) {
                  // Redirect to their vanity URL which loads their profile/fanzine
                  return '/$username';
                }
              }
            } catch (e) {
              print("Error fetching user shortcode for redirect: $e");
            }

            // Fallback: If no username found, send them to the generic authenticated fanzine dashboard
            return '/fanzine';
          }
          return null;
        }

        return null;
      },

      routes: [
        GoRoute(
          path: '/',
          name: 'root',
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
        // Fanzine Page - Handles both Public (Fanzine of the Week) and Private (User Dashboard) viewing
        GoRoute(
          path: '/fanzine',
          name: 'fanzine',
          builder: (context, state) => const FanzinePage(),
        ),
        // Private Profile Dashboard Route
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

        // PUBLIC: /:code (The "Traffic Cop" Route)
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