import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';

class FanzineSticker extends StatelessComponent {
  final AuthState? authState;

  const FanzineSticker({this.authState});

  @override
  Component build(BuildContext context) {
    final isLoggedIn = authState?.status == AuthStatus.authenticated;
    final username = authState?.user?.email?.split('@').first ?? 'guest';
    final linkText = isLoggedIn ? 'bqopd.com/$username' : 'Login / Register';
    final targetRoute = isLoggedIn ? '/profile' : '/login';

    return div(classes: 'manila-envelope', [
      div(classes: 'flex-row justify-center', [
        button(
            classes: 'nav-pill',
            events: {'click': (e) => Router.of(context).push(targetRoute)},
            [text(linkText)]
        )
      ]),
      div(classes: 'white-sticker', [
        h1(classes: 'font-bold text-lg text-center', [text('bqopd')]),
        p(classes: 'text-center mt-4 text-sm', [text('The Fanzine Platform')]),
        p(classes: 'text-center mt-2 text-xs text-gray', [text('Upload, Curate, and Share archival works.')]),
      ])
    ]);
  }
}