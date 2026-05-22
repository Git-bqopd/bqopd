import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'package:bqopd_core/bqopd_core.dart';
import 'repositories/repositories.dart';
import 'utils/web_firebase_interop.dart';

import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/profile_page.dart';
import 'pages/fanzine_reader_page.dart';
import 'pages/short_link_page.dart';

/// Client and Server-side master routing configuration.
class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final IAuthRepository authRepository;
  late final IFanzineRepository fanzineRepository;
  late final IEngagementRepository engagementRepository;
  late final IPipelineRepository pipelineRepository;
  late final IUploadRepository uploadRepository;
  late final IUserRepository userRepository;

  late final AuthBloc authBloc;
  late final UploadBloc uploadBloc;
  late final InteractionBloc interactionBloc;

  AuthState? authState;
  StreamSubscription? _sub;
  StreamSubscription? _modalSub;

  bool _hasError = false;
  String _errorMsg = '';
  bool _showGlobalLoginModal = false;

  @override
  void initState() {
    super.initState();
    try {
      authRepository = createAuthRepository();
      fanzineRepository = createFanzineRepository();
      engagementRepository = createEngagementRepository();
      pipelineRepository = createPipelineRepository();
      uploadRepository = createUploadRepository();
      userRepository = createUserRepository();

      uploadBloc = UploadBloc(repository: uploadRepository);
      interactionBloc = InteractionBloc(repository: engagementRepository);

      authBloc = AuthBloc(repository: authRepository)..add(AuthSubscriptionRequested());
      authState = authBloc.state;

      if (kIsWeb) {
        _sub = authBloc.stream.listen((state) {
          setState(() {
            authState = state;
          });
        });

        // Listen for global modal bus events (e.g. when a guest clicks Like)
        _modalSub = GlobalModalBus.stream.listen((show) {
          setState(() {
            _showGlobalLoginModal = show;
          });
        });
      }
    } catch (e) {
      _hasError = true;
      _errorMsg = e.toString();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _modalSub?.cancel();
    if (!_hasError) {
      authBloc.close();
      uploadBloc.close();
      interactionBloc.close();
    }
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    if (_hasError) {
      return div(classes: 'error-msg', [
        text('Error loading app: $_errorMsg')
      ]);
    }

    return div(id: 'app-root', [
      Router(
        routes: [
          Route(
            path: '/',
            builder: (context, state) => HomePage(authState: authState, authBloc: authBloc),
          ),
          Route(
            path: '/login',
            builder: (context, state) => LoginPage(authState: authState, authBloc: authBloc),
          ),
          Route(
            path: '/register',
            builder: (context, state) => RegisterPage(authState: authState, authBloc: authBloc),
          ),
          Route(
            path: '/profile',
            builder: (context, state) {
              if (state.queryParams['userId'] == null && authState?.status != AuthStatus.authenticated) {
                return LoginPage(authState: authState, authBloc: authBloc);
              }
              return ProfilePage(
                authState: authState,
                authBloc: authBloc,
                userRepository: userRepository,
                engagementRepository: engagementRepository,
              );
            },
          ),

          // UNCONDITIONAL ROUTES: Accessible by both server and browser environments.
          Route(
            path: '/reader/:fanzineId',
            builder: (context, state) => FanzineReaderPage(
              fanzineId: state.params['fanzineId']!,
              authState: authState,
              authBloc: authBloc,
            ),
          ),
          // Shortlink matcher
          Route(
            path: '/:code',
            builder: (context, state) => ShortLinkPage(
              code: state.params['code']!,
              authState: authState,
              authBloc: authBloc,
              userRepository: userRepository,
              engagementRepository: engagementRepository,
            ),
          ),
          // ULTRA-SHORT HIERARCHY PATTERN (/:code/:pageNumber)
          Route(
            path: '/:code/:pageNumber',
            builder: (context, state) => ShortLinkPage(
              code: state.params['code']!,
              pageNumber: state.params['pageNumber'],
              authState: authState,
              authBloc: authBloc,
              userRepository: userRepository,
              engagementRepository: engagementRepository,
            ),
          ),
        ],
      ),

      // Center Screen Floating Login Modal Layer
      if (_showGlobalLoginModal)
        _buildGlobalLoginModalOverlay(),
    ]);
  }

  Component _buildGlobalLoginModalOverlay() {
    return div(
        classes: 'global-modal-overlay',
        attributes: {
          'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
        },
        [
          div(
              classes: 'manila-envelope',
              attributes: {
                'style': 'max-width: 400px; max-height: 550px; border-radius: 12px; overflow: hidden; position: relative;'
              },
              [
                // High-fidelity Floating Close Button
                button(
                    classes: 'modal-close-btn',
                    attributes: {
                      'style': 'position: absolute; top: 12px; right: 12px; border: none; background: rgba(255,255,255,0.8); border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 16px; font-weight: bold; z-index: 200;'
                    },
                    events: {
                      'click': (e) {
                        setState(() {
                          _showGlobalLoginModal = false;
                        });
                      }
                    },
                    [text('×')]
                ),

                _GlobalModalLoginContent(
                  authState: authState,
                  authBloc: authBloc,
                  onSuccess: () {
                    setState(() {
                      _showGlobalLoginModal = false;
                    });
                  },
                )
              ]
          )
        ]
    );
  }
}

class _GlobalModalLoginContent extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc authBloc;
  final VoidCallback onSuccess;

  const _GlobalModalLoginContent({
    required this.authState,
    required this.authBloc,
    required this.onSuccess,
  });

  @override
  State<_GlobalModalLoginContent> createState() => _GlobalModalLoginContentState();
}

class _GlobalModalLoginContentState extends State<_GlobalModalLoginContent> {
  bool _isRegister = false;
  String _email = '';
  String _password = '';
  String _username = '';
  bool _loading = false;
  String? _error;

  @override
  Component build(BuildContext context) {
    if (_isRegister) {
      return div(classes: 'white-sticker p-6 w-full h-full flex flex-col justify-center items-center', [
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
                  setState(() { _loading = false; _error = null; });
                  component.onSuccess();
                } catch (e) {
                  setState(() { _error = e.toString(); _loading = false; });
                }
              }},
              [text(_loading ? 'loading...' : 'register')]
          ),
          if (_error != null)
            p(classes: 'error-msg mt-2', [text(_error!)]),
        ]),
        div(classes: 'flex-row gap-2 mt-4 text-xs justify-center w-full', [
          text('already cool? '),
          a(
              href: '#',
              classes: 'font-bold',
              events: {'click': (e) => setState(() { _isRegister = false; _error = null; })},
              [text('login here')]
          )
        ])
      ]);
    }

    return div(classes: 'white-sticker p-6 w-full h-full flex flex-col justify-center items-center', [
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
                setState(() { _loading = false; _error = null; });
                component.onSuccess();
              } catch (e) {
                setState(() { _error = e.toString(); _loading = false; });
              }
            }},
            [text(_loading ? 'loading...' : 'login')]
        ),
        if (_error != null)
          p(classes: 'error-msg mt-2', [text(_error!)]),
      ]),
      div(classes: 'flex-row gap-2 mt-4 text-xs justify-center w-full', [
        text('not cool yet? '),
        a(
            href: '#',
            classes: 'font-bold',
            events: {'click': (e) => setState(() { _isRegister = true; _error = null; })},
            [text('register here')]
        )
      ])
    ]);
  }
}