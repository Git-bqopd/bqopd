import 'package:go_router/go_router.dart';
import 'pages/auth_page.dart';
import 'pages/fanzine_page.dart';
import 'pages/not_found_page.dart';
import 'pages/resolver_page.dart';

final router = GoRouter(
  errorBuilder: (context, state) => const NotFoundPage(),
  routes: [
    GoRoute(path: '/', builder: (context, state) => const FanzinePage()),
    GoRoute(
      path: '/auth',
      builder: (context, state) {
        final ret = state.uri.queryParameters['return'];
        if (ret == null) {
          return const NotFoundPage();
        }
        final mode = state.uri.queryParameters['mode'];
        return AuthPage(returnParam: ret, mode: mode);
      },
    ),
    GoRoute(
      path: '/:slug',
      builder: (context, state) =>
          ResolverPage(slug: state.pathParameters['slug']!),
    ),
  ],
);
