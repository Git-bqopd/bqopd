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
      // This matches the behavior of the Flutter app's FanzineReaderPage initialization.
      final res = await fsGetDoc('app_settings/main_settings');
      final doc = jsonDecode(res);

      if (doc['exists'] == true) {
        final data = doc['data'];
        final loginZine = data['login_zine_shortcode'];

        if (loginZine != null && loginZine.toString().isNotEmpty) {
          // Push the shortcode to the router.
          // The ShortLinkPage will handle resolving this code to the actual reader view.
          if (mounted) {
            Router.of(context).replace('/$loginZine');
            return;
          }
        }
      }
    } catch (e) {
      print('Error fetching default route: $e');
    }

    // If we fail to find a redirect or an error occurs, stop loading and show the fallback UI
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
          classes: 'flex-col items-center justify-center w-full',
          attributes: {'style': 'min-height: 100vh;'},
          [p([text('Redirecting...')])]
      );
    }

    return div(
        classes: 'flex-col items-center justify-center w-full',
        attributes: {'style': 'min-height: 100vh;'},
        [
          FanzineSticker(authState: component.authState),

          if (component.authState?.status == AuthStatus.authenticated)
            div(classes: 'mt-4', [
              button(
                  classes: 'btn-logout',
                  events: {'click': (e) => component.authBloc.add(LogoutRequested())},
                  [text('Logout')]
              )
            ])
        ]
    );
  }
}