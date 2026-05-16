import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'env.dart';

import 'repositories/firebase_auth_repository.dart';
import 'repositories/firebase_user_repository.dart';
import 'repositories/firebase_engagement_repository.dart';
import 'repositories/firebase_upload_repository.dart';
import 'repositories/firebase_fanzine_repository.dart';
import 'repositories/firebase_pipeline_repository.dart';

import 'package:bqopd_core/bqopd_core.dart';
import 'services/user_provider.dart';

import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/profile_page.dart';
import 'pages/short_link_page.dart';
import 'pages/edit_info_page.dart';
import 'pages/settings_page.dart';
import 'pages/curator_dashboard_page.dart';
import 'pages/fanzine_reader_page.dart';
import 'pages/publisher_page.dart';
import 'pages/moderator_feed_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final authRepo = FirebaseAuthRepository();
  final userRepo = FirebaseUserRepository();
  final engagementRepo = FirebaseEngagementRepository();
  final uploadRepo = FirebaseUploadRepository();
  final fanzineRepo = FirebaseFanzineRepository();
  final pipelineRepo = FirebasePipelineRepository();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<IAuthRepository>.value(value: authRepo),
        RepositoryProvider<IUserRepository>.value(value: userRepo),
        RepositoryProvider<IEngagementRepository>.value(value: engagementRepo),
        RepositoryProvider<IUploadRepository>.value(value: uploadRepo),
        RepositoryProvider<IFanzineRepository>.value(value: fanzineRepo),
        RepositoryProvider<IPipelineRepository>.value(value: pipelineRepo),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(repository: context.read<IAuthRepository>())..add(AuthSubscriptionRequested()),
          ),
          BlocProvider(create: (context) => UploadBloc(repository: context.read<IUploadRepository>())),
          BlocProvider(create: (context) => InteractionBloc(repository: context.read<IEngagementRepository>())),
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

        // 1. DYNAMIC ROOT REDIRECTION
        if (path == '/') {
          if (isLoggedIn && userProvider.userAccount != null) {
            final coreBook = userProvider.userAccount!.preferences['core_book_shortcode'];
            if (coreBook != null && coreBook.toString().isNotEmpty) {
              return '/$coreBook';
            }
          }
          return null;
        }

        // 2. PROTECTED ROUTES
        final isProtected = path == '/profile' || path == '/settings' || path == '/edit-info' || path == '/dashboard' || path == '/moderator' || state.fullPath?.startsWith('/editor') == true;
        if (!isLoggedIn && isProtected) return '/login';
        if (isLoggedIn && (path == '/login' || path == '/register')) return '/';

        return null;
      },
      routes: [
        GoRoute(path: '/', name: 'root', builder: (context, state) => const FanzineReaderPage()),
        GoRoute(path: '/login', name: 'login', builder: (context, state) => const LoginPage()),
        GoRoute(path: '/register', name: 'register', builder: (context, state) => const RegisterPage()),
        GoRoute(path: '/profile', name: 'profile', builder: (context, state) => const ProfilePage()),
        GoRoute(path: '/dashboard', name: 'curatorDashboard', builder: (context, state) => const CuratorDashboardPage()),
        GoRoute(path: '/moderator', name: 'moderatorFeed', builder: (context, state) => const ModeratorFeedPage()),
        GoRoute(path: '/reader/:fanzineId', name: 'reader', builder: (context, state) => FanzineReaderPage(fanzineId: state.pathParameters['fanzineId']!)),
        GoRoute(path: '/publisher', name: 'publisher', builder: (context, state) => const PublisherPage()),
        GoRoute(path: '/edit-info', name: 'editInfo', builder: (context, state) => EditInfoPage(targetUserId: state.uri.queryParameters['userId'])),
        GoRoute(path: '/settings', name: 'settings', builder: (context, state) => const SettingsPage()),
        GoRoute(path: '/editor/:fanzineId', name: 'fanzineEditor', builder: (context, state) => FanzineReaderPage(fanzineId: state.pathParameters['fanzineId']!, isEditingMode: true)),

        // 3. SHORTCODE MATCHERS (including path variable anchors)
        GoRoute(
          path: '/:code',
          name: 'shortlink',
          builder: (context, state) {
            final code = state.pathParameters['code']!;
            final pQuery = state.uri.queryParameters['p'];
            final int? initialPage = pQuery != null ? int.tryParse(pQuery) : null;
            return ShortLinkPage(code: code, initialPageNumber: initialPage);
          },
        ),
        GoRoute(
          path: '/:code/:pageNumber',
          name: 'shortlink_with_page',
          builder: (context, state) {
            final code = state.pathParameters['code']!;
            final pageNumberStr = state.pathParameters['pageNumber']!;
            return ShortLinkPage(code: code, initialPageNumber: int.tryParse(pageNumberStr));
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