import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

class FanzineSticker extends StatefulComponent {
  final AuthState? authState;

  const FanzineSticker({this.authState});

  @override
  State<FanzineSticker> createState() => _FanzineStickerState();
}

class _FanzineStickerState extends State<FanzineSticker> {
  bool _showLogin = false;
  bool _showRegister = false;
  String _email = '';
  String _password = '';
  String _username = '';
  bool _loading = false;
  String? _error;

  @override
  Component build(BuildContext context) {
    final isLoggedIn = component.authState?.status == AuthStatus.authenticated;
    final username = component.authState?.user?.email?.split('@').first ?? 'guest';
    final linkText = isLoggedIn ? 'bqopd.com/$username' : 'Login / Register';

    if (isLoggedIn) {
      _showLogin = false;
      _showRegister = false;
    }

    if (_showLogin) {
      return div(classes: 'manila-envelope', [
        div(classes: 'flex-row justify-between w-full px-2 mb-2', [
          button(
              classes: 'nav-pill',
              events: {'click': (e) => setState(() => _showLogin = false)},
              [text('Back')]
          ),
          button(
              classes: 'nav-pill',
              events: {'click': (e) => setState(() { _showLogin = false; _showRegister = true; _error = null; })},
              [text('Register')]
          )
        ]),
        div(classes: 'white-sticker p-4', [
          h1(classes: 'font-bold text-lg text-center mb-2', [text('Login to bqopd')]),
          div(classes: 'flex-col w-full mt-2', [
            input(
              attributes: {'type': 'email', 'placeholder': 'email', 'value': _email},
              events: {'input': (e) => _email = (e.target as dynamic).value},
            ),
            input(
              attributes: {'type': 'password', 'placeholder': 'password', 'value': _password},
              events: {'input': (e) => _password = (e.target as dynamic).value},
            ),
            button(
                classes: 'btn-primary mt-2',
                events: {'click': (e) async {
                  if (_email.trim().isEmpty || _password.isEmpty) {
                    setState(() => _error = "Please fill all fields.");
                    return;
                  }
                  setState(() => _loading = true);
                  try {
                    await loginWithFirebase(_email.trim(), _password);
                    setState(() { _showLogin = false; _loading = false; _error = null; });
                  } catch (e) {
                    setState(() { _error = e.toString(); _loading = false; });
                  }
                }},
                [text(_loading ? 'loading...' : 'login')]
            ),
            if (_error != null)
              p(classes: 'error-msg mt-2', [text(_error!)]),
          ])
        ])
      ]);
    }

    if (_showRegister) {
      return div(classes: 'manila-envelope', [
        div(classes: 'flex-row justify-between w-full px-2 mb-2', [
          button(
              classes: 'nav-pill',
              events: {'click': (e) => setState(() => _showRegister = false)},
              [text('Back')]
          ),
          button(
              classes: 'nav-pill',
              events: {'click': (e) => setState(() { _showRegister = false; _showLogin = true; _error = null; })},
              [text('Login')]
          )
        ]),
        div(classes: 'white-sticker p-4', [
          h1(classes: 'font-bold text-lg text-center mb-2', [text('Register to bqopd')]),
          div(classes: 'flex-col w-full mt-2', [
            input(
              attributes: {'type': 'text', 'placeholder': 'username', 'value': _username},
              events: {'input': (e) => _username = (e.target as dynamic).value},
            ),
            input(
              attributes: {'type': 'email', 'placeholder': 'email', 'value': _email},
              events: {'input': (e) => _email = (e.target as dynamic).value},
            ),
            input(
              attributes: {'type': 'password', 'placeholder': 'password', 'value': _password},
              events: {'input': (e) => _password = (e.target as dynamic).value},
            ),
            button(
                classes: 'btn-primary mt-2',
                events: {'click': (e) async {
                  if (_username.trim().isEmpty || _email.trim().isEmpty || _password.isEmpty) {
                    setState(() => _error = "Please fill all fields.");
                    return;
                  }
                  setState(() => _loading = true);
                  try {
                    await registerWithFirebase(_email.trim(), _password, _username.trim());
                    setState(() { _showRegister = false; _loading = false; _error = null; });
                  } catch (e) {
                    setState(() { _error = e.toString(); _loading = false; });
                  }
                }},
                [text(_loading ? 'loading...' : 'register')]
            ),
            if (_error != null)
              p(classes: 'error-msg mt-2', [text(_error!)]),
          ])
        ])
      ]);
    }

    return div(classes: 'manila-envelope', [
      div(classes: 'flex-row justify-center', [
        button(
            classes: 'nav-pill',
            events: {'click': (e) => setState(() => _showLogin = true)},
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