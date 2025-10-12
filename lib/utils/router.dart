import 'dart:async';

import 'package:bqopd/components/app_wrapper.dart';
import 'package:bqopd/pages/edit_info_page.dart';
import 'package:bqopd/pages/fanzine_editor_page.dart';
import 'package:bqopd/pages/fanzine_page.dart';
import 'package:bqopd/pages/login_page.dart';
import 'package:bqopd/pages/profile_page.dart';
import 'package:bqopd/pages/register_page.dart';
import 'package:bqopd/pages/settings_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Listenable that refreshes the router when the provided stream emits.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final GoRouter router = GoRouter(
  initialLocation: '/',
  navigatorKey: _rootNavigatorKey,
  refreshListenable:
      GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
  redirect: (context, state) {
    final bool loggedIn = FirebaseAuth.instance.currentUser != null;
    final bool goingToLogin = state.matchedLocation == '/login';
    final bool goingToRegister = state.matchedLocation == '/register';

    if (!loggedIn && !(goingToLogin || goingToRegister)) return '/login';
    if (loggedIn && (goingToLogin || goingToRegister)) return '/';
    return null;
  },
  routes: <RouteBase>[
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return AppWrapper(navigationShell: child as StatefulNavigationShell);
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const FanzinePage(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfilePage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/fanzine/:shortcode',
      builder: (context, state) {
        final shortcode = state.pathParameters['shortcode']!;
        return FanzinePage(shortcode: shortcode);
      },
    ),
    GoRoute(
      path: '/editor/:fanzineId',
      builder: (context, state) {
        final fanzineId = state.pathParameters['fanzineId']!;
        return FanzineEditorPage(fanzineId: fanzineId);
      },
    ),
    GoRoute(
      path: '/edit-info',
      builder: (context, state) => const EditInfoPage(),
    ),
  ],
);
