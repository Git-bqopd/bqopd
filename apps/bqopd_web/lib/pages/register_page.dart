import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/src/blocs/auth/auth_bloc.dart';
import '../components/page_wrapper.dart';
import '../utils/web_utils.dart';

/// User registration page for the bqopd web application.
/// Manages new account registration inputs and auth BLoC interactions.
class RegisterPage extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc authBloc;

  const RegisterPage({
    required this.authState,
    required this.authBloc,
    super.key,
  });

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
            child: div(
              classes: 'flex-col items-center gap-4',
              [
                p([Component.text('You are already logged in.')]),
                a(href: '/', [Component.text('Go Home')]),
              ],
            ),
          ),
        ],
      );
    }

    final isLoading = component.authState?.status == AuthStatus.loading;

    return div(
      classes: 'flex-col items-center justify-center w-full',
      attributes: const {'style': 'min-height: 100vh;'},
      [
        PageWrapper(
          child: div(
            classes: 'flex-col items-center w-full',
            [
              h1(classes: 'text-lg font-bold', [Component.text('bqopd')]),
              p([Component.text('Register a new account')]),
              div(
                classes: 'flex-col w-full mt-4',
                [
                  input(
                    attributes: const {'type': 'text', 'placeholder': 'username'},
                    events: {'input': (e) => _username = getInputValue(e)},
                  ),
                  input(
                    attributes: const {'type': 'email', 'placeholder': 'email'},
                    events: {'input': (e) => _email = getInputValue(e)},
                  ),
                  input(
                    attributes: const {'type': 'password', 'placeholder': 'password'},
                    events: {'input': (e) => _password = getInputValue(e)},
                  ),
                  button(
                    classes: 'btn-primary',
                    events: {
                      'click': (e) {
                        if (!isLoading) {
                          // Sanitize email and username to avoid whitespace-related SDK failures
                          component.authBloc.add(
                            RegisterRequested(
                              email: _email.trim(),
                              password: _password,
                              username: _username.trim(),
                            ),
                          );
                        }
                      },
                    },
                    [Component.text(isLoading ? 'loading...' : 'register')],
                  ),
                ],
              ),
              if (component.authState?.status == AuthStatus.failure)
                p(
                  classes: 'error-msg',
                  [
                    Component.text(
                      component.authState?.errorMessage ?? 'Registration failed',
                    ),
                  ],
                ),
              div(
                classes: 'flex-row gap-2 mt-4',
                [
                  Component.text('already cool? '),
                  a(
                    href: '/login',
                    classes: 'font-bold',
                    [Component.text('login here')],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}