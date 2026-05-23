import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/src/blocs/auth/auth_bloc.dart';
import '../components/page_wrapper.dart';

class LoginPage extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc authBloc;

  const LoginPage({required this.authState, required this.authBloc});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String _email = '';
  String _password = '';

  @override
  Component build(BuildContext context) {
    // In Jaspr 0.23+, use `component` to access parent properties
    if (component.authState?.status == AuthStatus.authenticated) {
      return div(
          classes: 'flex-col items-center justify-center w-full',
          attributes: const {'style': 'min-height: 100vh;'},
          [
            PageWrapper(
                child: div(classes: 'flex-col items-center gap-4', [
                  p([text('You are already logged in.')]),
                  a(href: '/', [text('Go Home')])
                ])
            )
          ]
      );
    }

    final isLoading = component.authState?.status == AuthStatus.loading;

    return div(
        classes: 'flex-col items-center justify-center w-full',
        attributes: const {'style': 'min-height: 100vh;'},
        [
          PageWrapper(
              child: div(classes: 'flex-col items-center w-full', [
                h1(classes: 'text-lg font-bold', [text('bqopd')]),
                p([text('Login to your account')]),

                div(classes: 'flex-col w-full mt-4', [
                  input(
                    attributes: {'type': 'email', 'placeholder': 'email'},
                    events: {'input': (e) => _email = (e.target as dynamic).value},
                  ),
                  input(
                    attributes: {'type': 'password', 'placeholder': 'password'},
                    events: {'input': (e) => _password = (e.target as dynamic).value},
                  ),
                  button(
                      classes: 'btn-primary',
                      events: {
                        'click': (e) {
                          if (!isLoading) {
                            // Normalize the input by trimming trailing and leading whitespace
                            component.authBloc.add(LoginRequested(_email.trim(), _password));
                          }
                        }
                      },
                      [text(isLoading ? 'loading...' : 'login')]
                  ),
                ]),

                if (component.authState?.status == AuthStatus.failure)
                  p(classes: 'error-msg', [text(component.authState?.errorMessage ?? 'Login failed')]),

                div(classes: 'flex-row gap-2 mt-4', [
                  text('not cool yet? '),
                  a(href: '/register', classes: 'font-bold', [text('register here')])
                ])
              ])
          )
        ]
    );
  }
}