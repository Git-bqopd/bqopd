import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
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

      redirect: (context, state) async { // Async redirect
        final user = FirebaseAuth.instance.currentUser;
        final path = state.fullPath ?? '/';

        final isLoggingIn = path == '/login' || path == '/register';
        final isRoot = path == '/';
        final isProtected = path == '/fanzine' || path == '/profile';

        // 1. Unauthenticated User Logic
        if (user == null) {
          if (isRoot || isProtected) {
            return '/login';
          }
          // Allow public access to login, register, and shortlinks
          return null;
        }

        // 2. Authenticated User Logic
        if (user != null) {
          // If going to Root, Login, Register, OR the old /fanzine route
          if (isRoot || isLoggingIn || path == '/fanzine') {

            // Fetch the user's shortcode preference
            try {
              final doc = await FirebaseFirestore.instance
                  .collection('Users')
                  .doc(user.uid)
                  .get();

              if (doc.exists) {
                final data = doc.data();
                final shortCode = data?['newFanzine'] as String?;

                // If they have a shortcode, send them there!
                if (shortCode != null && shortCode.isNotEmpty) {
                  return '/$shortCode';
                }
              }
            } catch (e) {
              print("Error fetching user shortcode for redirect: $e");
            }

            // Fallback if no shortcode found or error
            // We can send them to a generic 'fanzine' route, or keep them on current path
            // But to avoid infinite loops, if we are already at /fanzine, return null.
            if (path != '/fanzine') {
              return '/fanzine';
            }
          }
          // Allow access to Profile and other pages
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
        // Keep /fanzine as a fallback route
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

        // PUBLIC: /:code
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