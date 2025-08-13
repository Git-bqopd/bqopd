import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth/auth.dart';
import 'pages/fanzine_page.dart';
import 'pages/not_found_page.dart';
import 'pages/resolver_page.dart';

final GoRouter router = GoRouter(
  errorBuilder: (context, state) => const NotFoundPage(),
  routes: [
    // App entry — AuthPage decides: show login/register (unauthed) or continue.
    GoRoute(
      path: '/',
      builder: (context, state) => const AuthPage(),
    ),

    // Deep-linkable auth page with return + optional mode
    GoRoute(
      path: '/auth',
      builder: (context, state) => AuthPage(
        returnParam: state.uri.queryParameters['return'],
        mode: state.uri.queryParameters['mode'],
      ),
    ),

    // Your existing fanzine page (keep if you still navigate here anywhere)
    GoRoute(
      path: '/fanzine_page',
      builder: (context, state) => const FanzinePage(),
    ),

    // Prefixless resolver: /:slug handles shortcodes & vanity names
    GoRoute(
      path: '/:slug',
      builder: (context, state) =>
          ResolverPage(slug: state.pathParameters['slug']!),
    ),
  ],
);
