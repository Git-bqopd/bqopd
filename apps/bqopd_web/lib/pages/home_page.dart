import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/src/blocs/auth/auth_bloc.dart';
import '../components/fanzine_sticker.dart';
import '../utils/web_firebase_interop.dart';

class HomePage extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc authBloc;

  const HomePage({required this.authState, required this.authBloc});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkDefaultRoute();
  }

  Future<void> _checkDefaultRoute() async {
    try {
      // Check Firebase for the global login_zine_shortcode
      final res = await fsGetDoc('app_settings/main_settings');
      final doc = jsonDecode(res);

      if (doc['exists'] == true) {
        final data = doc['data'];
        final loginZine = data['login_zine_shortcode'];

        if (loginZine != null && loginZine.toString().isNotEmpty) {
          // Push the shortcode to route through ShortLinkPage resolution
          Router.of(context).push('/$loginZine');
          return;
        }
      }
    } catch (e) {
      print('Error fetching default route: $e');
    }

    // If we fail or the setting is empty, fall back to showing the sticker
    setState(() => _loading = false);
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
        p([text('Redirecting...')])
      ]);
    }

    return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
      FanzineSticker(authState: component.authState),

      if (component.authState?.status == AuthStatus.authenticated)
        div(classes: 'mt-4', [
          button(
              classes: 'btn-logout',
              events: {'click': (e) => component.authBloc.add(LogoutRequested())},
              [text('Logout')]
          )
        ])
    ]);
  }
}