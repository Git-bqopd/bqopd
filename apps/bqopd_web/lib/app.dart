import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart'; // Restored: Required for Router and Route components

// BLoC & Firebase Repository from the shared core
import 'package:bqopd_core/src/blocs/auth/auth_bloc.dart';
import 'repositories/web_auth_repository.dart';

// UI Pages
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
  late final WebAuthRepository authRepository;
  late final AuthBloc authBloc;
  AuthState? authState;
  StreamSubscription? _sub;

  bool _hasError = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    try {
      // Initialize our JS Interop Auth Repository
      authRepository = WebAuthRepository();

      // Inject it into our shared Core BLoC
      authBloc = AuthBloc(repository: authRepository)..add(AuthSubscriptionRequested());
      authState = authBloc.state;

      // Listen to state changes to rebuild the Routing layer
      _sub = authBloc.stream.listen((state) {
        setState(() {
          authState = state;
        });
      });
    } catch (e) {
      // Catch initialization errors (like JS interop issues) to prevent a blank white screen
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

    // Wrap the router in a standard div to ensure stable DOM mounting
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
              // Protected Route Logic
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