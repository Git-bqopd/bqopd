import 'package:bqopd/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth/auth.dart';
import 'auth/login_or_register.dart';
import 'pages/fanzine_page.dart';
import 'pages/not_found_page.dart';
import 'pages/resolver_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GoRouter _router = GoRouter(
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthPage()),
      GoRoute(path: '/auth', builder: (context, state) => const AuthPage()),
      GoRoute(
          path: '/login_register_page',
          builder: (context, state) => const LoginOrRegister()),
      GoRoute(
          path: '/fanzine_page',
          builder: (context, state) => const FanzinePage()),
      GoRoute(
        path: '/:slug',
        builder: (context, state) =>
            ResolverPage(slug: state.pathParameters['slug']!),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      ),
    );
  }
}
