import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'env.dart';

// Services & Repositories
import 'services/user_provider.dart';
import 'repositories/user_repository.dart';
import 'repositories/fanzine_repository.dart';
import 'repositories/pipeline_repository.dart';
import 'repositories/engagement_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/upload_repository.dart';

// BLoCs
import 'blocs/auth/auth_bloc.dart';
import 'blocs/upload/upload_bloc.dart';
import 'blocs/interaction/interaction_bloc.dart';

// Pages
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/profile_page.dart';
import 'pages/short_link_page.dart';
import 'pages/edit_info_page.dart';
import 'pages/settings_page.dart';
import 'pages/fanzine_reader_page.dart';
import 'pages/publisher_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  usePathUrlStrategy();

  // Initialize Repositories
  final authRepository = AuthRepository();
  final uploadRepository = UploadRepository();
  final engagementRepository = EngagementRepository();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: uploadRepository),
        RepositoryProvider.value(value: engagementRepository),
        RepositoryProvider(create: (_) => UserRepository()),
        RepositoryProvider(create: (_) => FanzineRepository()),
        RepositoryProvider(create: (_) => PipelineRepository()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(repository: authRepository)..add(AuthSubscriptionRequested()),
          ),
          BlocProvider(
            create: (context) => UploadBloc(repository: uploadRepository),
          ),
          BlocProvider(
            create: (context) => InteractionBloc(repository: engagementRepository),
          ),
        ],
        child: ChangeNotifierProvider(
          create: (_) => UserProvider(),
          child: const MyApp(),
        ),
      ),
    ),
  );
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
      refreshListenable: Provider.of<UserProvider>(context, listen: false),
      redirect: (context, state) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final isLoggedIn = userProvider.isLoggedIn;
        final path = state.uri.path;
        final routePattern = state.fullPath;

        final isProtected = path == '/profile' ||
            path == '/settings' ||
            path == '/edit-info' ||
            (routePattern != null && routePattern.startsWith('/editor'));

        if (!isLoggedIn && isProtected) {
          return '/login';
        }
        if (isLoggedIn && (path == '/login' || path == '/register')) {
          return '/';
        }
        return null;
      },
      routes: [
        GoRoute(
            path: '/',
            name: 'root',
            builder: (context, state) => const FanzineReaderPage()),
        GoRoute(
            path: '/login',
            name: 'login',
            builder: (context, state) => const LoginPage()),
        GoRoute(
            path: '/register',
            name: 'register',
            builder: (context, state) => const RegisterPage()),
        GoRoute(
            path: '/fanzine',
            name: 'fanzine',
            builder: (context, state) => const FanzineReaderPage()),
        GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfilePage()),
        GoRoute(
          path: '/reader/:fanzineId',
          name: 'reader',
          builder: (context, state) {
            final fanzineId = state.pathParameters['fanzineId']!;
            return FanzineReaderPage(fanzineId: fanzineId);
          },
        ),
        GoRoute(
          path: '/publisher',
          name: 'publisher',
          builder: (context, state) => const PublisherPage(),
        ),
        GoRoute(
          path: '/edit-info',
          name: 'editInfo',
          builder: (context, state) {
            final userId = state.uri.queryParameters['userId'];
            return EditInfoPage(targetUserId: userId);
          },
        ),
        GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsPage()),
        GoRoute(
          path: '/editor/:fanzineId',
          name: 'fanzineEditor',
          builder: (context, state) {
            final fanzineId = state.pathParameters['fanzineId']!;
            return FanzineReaderPage(
              fanzineId: fanzineId,
              isEditingMode: true,
            );
          },
        ),
        // FIXED: Using nested routes to reliably handle both /CODE and /CODE/PAGE
        GoRoute(
          path: '/:code',
          name: 'shortlink',
          builder: (context, state) {
            final code = state.pathParameters['code']!;
            return ShortLinkPage(code: code);
          },
          routes: [
            GoRoute(
              path: ':page',
              builder: (context, state) {
                final code = state.pathParameters['code']!;
                final page = state.pathParameters['page'];
                return ShortLinkPage(code: code, pageNumber: page);
              },
            ),
          ],
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