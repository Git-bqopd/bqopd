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

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  // --- Repositories ---
  late final WebAuthRepository authRepository;
  late final WebFanzineRepository fanzineRepository;
  late final WebEngagementRepository engagementRepository;
  late final WebPipelineRepository pipelineRepository;
  late final WebUploadRepository uploadRepository;
  late final WebUserRepository userRepository;

  // --- BLoCs ---
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
      // 1. Initialize Repositories via Web JS Interop
      authRepository = WebAuthRepository();
      fanzineRepository = WebFanzineRepository();
      engagementRepository = WebEngagementRepository();
      pipelineRepository = WebPipelineRepository();
      uploadRepository = WebUploadRepository();
      userRepository = WebUserRepository();

      // 2. Initialize Shared BLoCs
      uploadBloc = UploadBloc(repository: uploadRepository);
      interactionBloc = InteractionBloc(repository: engagementRepository);

      authBloc = AuthBloc(repository: authRepository)..add(AuthSubscriptionRequested());
      authState = authBloc.state;

      // 3. Listen to state changes to rebuild the Routing layer
      _sub = authBloc.stream.listen((state) {
        setState(() {
          authState = state;
        });
      });
    } catch (e) {
      _hasError = true;
      _errorMsg = e.toString();
      print("App Initialization Error: $e");
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
        text('Error loading app: $_errorMsg. Please check the console.')
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
              if (authState?.status != AuthStatus.authenticated) {
                return LoginPage(authState: authState, authBloc: authBloc);
              }
              return ProfilePage(authState: authState, authBloc: authBloc);
            },
          ),
        ],
      )
    ]);
  }
}