import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/src/blocs/auth/auth_bloc.dart';
import '../components/page_wrapper.dart';

class HomePage extends StatelessComponent {
  final AuthState? authState;
  final AuthBloc authBloc;

  const HomePage({required this.authState, required this.authBloc});

  @override
  Component build(BuildContext context) {
    return PageWrapper(
        child: div(classes: 'flex-col items-center w-full', [
          h1(classes: 'text-lg font-bold', [text('bqopd')]),
          p(classes: 'text-center mt-4', [text('The fanzine platform. Select a route to continue.')]),

          div(classes: 'flex-row gap-4 mt-4 items-center', [
            a(href: '/profile', [text('My Profile')]),

            if (authState?.status == AuthStatus.authenticated)
              button(
                  classes: 'btn-logout',
                  events: {'click': (e) => authBloc.add(LogoutRequested())},
                  [text('Logout')]
              )
            else
              a(href: '/login', [text('Login')]),
          ])
        ])
    );
  }
}