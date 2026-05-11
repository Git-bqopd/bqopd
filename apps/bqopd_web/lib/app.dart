import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart'; // REQUIRED for Jaspr 0.23.x

// Targeted imports to completely bypass the master bqopd_core.dart (which houses Flutter imports)
import 'package:bqopd_core/src/blocs/auth/auth_bloc.dart';
import 'repositories/web_auth_repository.dart';

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

  String _email = '';
  String _password = '';

  @override
  void initState() {
    super.initState();
    // 1. Initialize our JS Interop Auth Repository
    authRepository = WebAuthRepository();

    // 2. Inject it into our shared Core BLoC
    authBloc = AuthBloc(repository: authRepository)..add(AuthSubscriptionRequested());
    authState = authBloc.state;

    // 3. Listen to state changes and rebuild the Jaspr UI
    _sub = authBloc.stream.listen((state) {
      setState(() {
        authState = state;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    authBloc.close();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'app-container', [
      h1([text('bqopd Jaspr Web App')]),
      p([text('System Stable. UI Rendering successfully!')]),

      div(classes: 'core-test', [
        h3([text('Phase 5 Complete:')]),
        p([text('Firebase and Auth BLoC successfully integrated into Jaspr using Interface Abstraction!')]),

        div(classes: 'auth-status', [
          p([text('Auth Status: ${authState?.status.name ?? "unknown"}')]),
          p([text('User Email: ${authState?.user?.email ?? "none"}')]),
        ]),

        // Interactive HTML to test the BLoC integration
        if (authState?.status == AuthStatus.authenticated)
          button(
              classes: 'logout-btn',
              events: {'click': (e) {
                authBloc.add(LogoutRequested());
              }},
              [text('Logout')]
          )
        else
          div(classes: 'auth-form', [
            input(
              attributes: {'type': 'email', 'placeholder': 'Email'},
              events: {'input': (e) => _email = (e.target as dynamic).value},
            ),
            input(
              attributes: {'type': 'password', 'placeholder': 'Password'},
              events: {'input': (e) => _password = (e.target as dynamic).value},
            ),
            button(
                events: {'click': (e) {
                  if (_email.isNotEmpty && _password.isNotEmpty) {
                    authBloc.add(LoginRequested(_email, _password));
                  }
                }},
                [text('Login')]
            ),

            if (authState?.status == AuthStatus.failure)
              p(classes: 'error-msg', [text(authState?.errorMessage ?? 'Login failed.')])
          ])
      ])
    ]);
  }
}