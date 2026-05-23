import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/src/blocs/auth/auth_bloc.dart';
import '../components/page_wrapper.dart';

class RegisterPage extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc authBloc;

  const RegisterPage({required this.authState, required this.authBloc});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  String _email = '';
  String _password = '';
  String _username = '';

  @override
  Component build(BuildContext context) {
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
                p([text('Register a new account')]),

                div(classes: 'flex-col w-full mt-4', [
                  input(
                    attributes: {'type': 'text', 'placeholder': 'username'},
                    events: {'input': (e) => _username = (e.target as dynamic).value},
                  ),
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
                            // Sanitize email and username to avoid whitespace-related SDK failures
                            component.authBloc.add(RegisterRequested(
                                email: _email.trim(),
                                password: _password,
                                username: _username.trim()
                            ));
                          }
                        }
                      },
                      [text(isLoading ? 'loading...' : 'register')]
                  ),
                ]),

                if (component.authState?.status == AuthStatus.failure)
                  p(classes: 'error-msg', [text(component.authState?.errorMessage ?? 'Registration failed')]),

                div(classes: 'flex-row gap-2 mt-4', [
                  text('already cool? '),
                  a(href: '/login', classes: 'font-bold', [text('login here')])
                ])
              ])
          )
        ]
    );
  }
}