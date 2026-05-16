import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'package:bqopd_core/bqopd_core.dart';
import 'repositories/web_auth_repository.dart';
import 'repositories/web_engagement_repository.dart';
import 'repositories/web_fanzine_repository.dart';
import 'repositories/web_pipeline_repository.dart';
import 'repositories/web_upload_repository.dart';
import 'repositories/web_user_repository.dart';

import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/profile_page.dart';
import 'pages/fanzine_reader_page.dart';
import 'pages/short_link_page.dart';

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final WebAuthRepository authRepository;
  late final WebFanzineRepository fanzineRepository;
  late final WebEngagementRepository engagementRepository;
  late final WebPipelineRepository pipelineRepository;
  late final WebUploadRepository uploadRepository;
  late final WebUserRepository userRepository;

  late final AuthBloc authBloc;
  late final UploadBloc uploadBloc;
  late final InteractionBloc interactionBloc;

  AuthState? authState;
  StreamSubscription? _sub;

  bool _hasError = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    try {
      authRepository = WebAuthRepository();
      fanzineRepository = WebFanzineRepository();
      engagementRepository = WebEngagementRepository();
      pipelineRepository = WebPipelineRepository();
      uploadRepository = WebUploadRepository();
      userRepository = WebUserRepository();

      uploadBloc = UploadBloc(repository: uploadRepository);
      interactionBloc = InteractionBloc(repository: engagementRepository);

      authBloc = AuthBloc(repository: authRepository)..add(AuthSubscriptionRequested());
      authState = authBloc.state;

      _sub = authBloc.stream.listen((state) {
        setState(() {
          authState = state;
        });
      });
    } catch (e) {
      _hasError = true;
      _errorMsg = e.toString();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (!_hasError) {
      authBloc.close();
      uploadBloc.close();
      interactionBloc.close();
    }
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    if (_hasError) {
      return div(classes: 'error-msg', [
        text('Error loading app: $_errorMsg')
      ]);
    }

    return div(id: 'app-root', [
      Router(
        routes: [
          Route(
            path: '/',
            builder: (context, state) => HomePage(authState: authState, authBloc: authBloc),
          ),
          Route(
            path: '/login',
            builder: (context, state) => LoginPage(authState: authState, authBloc: authBloc),
          ),
          Route(
            path: '/register',
            builder: (context, state) => RegisterPage(authState: authState, authBloc: authBloc),
          ),
          Route(
            path: '/profile',
            builder: (context, state) {
              if (state.queryParams['userId'] == null && authState?.status != AuthStatus.authenticated) {
                return LoginPage(authState: authState, authBloc: authBloc);
              }
              return ProfilePage(authState: authState, authBloc: authBloc);
            },
          ),
          Route(
            path: '/reader/:fanzineId',
            builder: (context, state) => FanzineReaderPage(
              fanzineId: state.params['fanzineId']!,
            ),
          ),
          // Shortlink matcher
          Route(
            path: '/:code',
            builder: (context, state) => ShortLinkPage(
              code: state.params['code']!,
              authState: authState,
              authBloc: authBloc,
            ),
          ),
          // NEW: ULTRA-SHORT HIERARCHY PATTERN (/:code/:pageNumber)
          Route(
            path: '/:code/:pageNumber',
            builder: (context, state) => ShortLinkPage(
              code: state.params['code']!,
              pageNumber: state.params['pageNumber'],
              authState: authState,
              authBloc: authBloc,
            ),
          ),
        ],
      )
    ]);
  }
}