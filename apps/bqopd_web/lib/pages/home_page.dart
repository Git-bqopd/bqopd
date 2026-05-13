import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/src/blocs/auth/auth_bloc.dart';
import '../components/fanzine_sticker.dart';

class HomePage extends StatelessComponent {
  final AuthState? authState;
  final AuthBloc authBloc;

  const HomePage({required this.authState, required this.authBloc});

  @override
  Component build(BuildContext context) {
    return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
      FanzineSticker(authState: authState),

      if (authState?.status == AuthStatus.authenticated)
        div(classes: 'mt-4', [
          button(
              classes: 'btn-logout',
              events: {'click': (e) => authBloc.add(LogoutRequested())},
              [text('Logout')]
          )
        ])
    ]);
  }
}