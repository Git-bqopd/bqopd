import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import 'repositories/repositories.dart';
import 'utils/web_firebase_interop.dart';
import 'utils/web_utils.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/profile_page.dart';
import 'pages/edit_info_page.dart';
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
                userId: state.queryParams['userId'],
              );
            },
          ),
          // EDIT INFO ROUTE: Registered explicitly before wildcard matchers
          Route(
            path: '/edit-info',
            builder: (context, state) {
              if (authState?.status != AuthStatus.authenticated && state.queryParams['userId'] == null) {
                return LoginPage(authState: authState, authBloc: authBloc);
              }
              return EditInfoPage(
                authState: authState,
                authBloc: authBloc,
                userRepository: userRepository,
                targetUserId: state.queryParams['userId'],
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
          // MASTER FOLIO WEB EDITOR ROUTE
          Route(
            path: '/editor/:fanzineId',
            builder: (context, state) => FanzineReaderPage(
              fanzineId: state.params['fanzineId']!,
              isEditingMode: true,
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
        attributes: const {
          'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
        },
        [
          div(
              classes: 'manila-envelope',
              attributes: const {
                'style': 'max-width: 400px; max-height: 550px; border-radius: 12px; overflow: hidden; position: relative;'
              },
              [
                // High-fidelity Floating Close Button
                button(
                    classes: 'modal-close-btn',
                    attributes: const {
                      'style': 'position: absolute; top: 12px; right: 12px; border: none; background: rgba(255,255,255,0.8); border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 16px; font-weight: bold; z-index: 200;'
                    },
                    events: {
                      'click': (e) {
                        setState(() {
                          _showGlobalLoginModal = false;
                        });
                      }
                    },
                    [text('✕')]
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
  final void Function() onSuccess;

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
      return div(
          classes: 'white-sticker',
          attributes: const {
            'style': 'padding: 24px; display: flex; flex-direction: column; justify-content: center; align-items: center; width: 85%; height: 80%; box-sizing: border-box;'
          },
          [
            img(
                src: 'assets/logo200.gif',
                attributes: const {
                  'style': 'width: 80px; height: auto; display: block; margin-bottom: 8px;'
                }
            ),
            div(
                attributes: const {
                  'style': 'font-size: 16px; font-weight: 500; color: #222; margin-bottom: 20px; font-family: inherit; letter-spacing: 0.5px;'
                },
                [text('bqopd')]
            ),
            div(
                classes: 'flex-col w-full',
                attributes: const {
                  'style': 'display: flex; flex-direction: column; width: 100%; gap: 10px;'
                },
                [
                  input(
                    attributes: const {
                      'type': 'text',
                      'placeholder': 'username',
                      'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                    },
                    events: {'input': (e) => _username = getInputValue(e)},
                  ),
                  input(
                    attributes: const {
                      'type': 'email',
                      'placeholder': 'email',
                      'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                    },
                    events: {'input': (e) => _email = getInputValue(e)},
                  ),
                  input(
                    attributes: const {
                      'type': 'password',
                      'placeholder': 'password',
                      'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                    },
                    events: {'input': (e) => _password = getInputValue(e)},
                  ),
                  button(
                      classes: 'btn-primary',
                      attributes: const {
                        'style': 'width: 100%; padding: 12px; background-color: #8e8e8e; color: white; border: none; border-radius: 8px; font-size: 14px; font-weight: bold; cursor: pointer; transition: background-color 0.2s; margin-top: 4px;'
                      },
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
                          setState(() { _error = e.toString().replaceAll('Exception:', '').trim(); _loading = false; });
                        }
                      }},
                      [text(_loading ? 'loading...' : 'register')]
                  ),
                ]
            ),
            if (_error != null)
              p(
                  classes: 'error-msg',
                  attributes: const {
                    'style': 'color: #d9534f; font-size: 12px; margin-top: 8px; text-align: center;'
                  },
                  [text(_error!)]
              ),
            div(
                attributes: const {
                  'style': 'margin-top: 20px; font-size: 11px; color: #555; text-align: center;'
                },
                [
                  text('already cool? '),
                  span(
                      attributes: const {
                        'style': 'text-decoration: underline; cursor: pointer; font-weight: bold; color: #000;'
                      },
                      events: {'click': (e) => setState(() { _isRegister = false; _error = null; })},
                      [text('login here.')]
                  )
                ]
            )
          ]
      );
    }

    return div(
        classes: 'white-sticker',
        attributes: const {
          'style': 'padding: 24px; display: flex; flex-direction: column; justify-content: center; align-items: center; width: 85%; height: 80%; box-sizing: border-box;'
        },
        [
          img(
              src: 'assets/logo200.gif',
              attributes: const {
                'style': 'width: 80px; height: auto; display: block; margin-bottom: 8px;'
              }
          ),
          div(
              attributes: const {
                'style': 'font-size: 16px; font-weight: 500; color: #222; margin-bottom: 20px; font-family: inherit; letter-spacing: 0.5px;'
              },
              [text('bqopd')]
          ),
          div(
              classes: 'flex-col w-full',
              attributes: const {
                'style': 'display: flex; flex-direction: column; width: 100%; gap: 10px;'
              },
              [
                input(
                  attributes: const {
                    'type': 'email',
                    'placeholder': 'email',
                    'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                  },
                  events: {'input': (e) => _email = getInputValue(e)},
                ),
                input(
                  attributes: const {
                    'type': 'password',
                    'placeholder': 'password',
                    'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                  },
                  events: {'input': (e) => _password = getInputValue(e)},
                ),
                button(
                    classes: 'btn-primary',
                    attributes: const {
                      'style': 'width: 100%; padding: 12px; background-color: #8e8e8e; color: white; border: none; border-radius: 8px; font-size: 14px; font-weight: bold; cursor: pointer; transition: background-color 0.2s; margin-top: 4px;'
                    },
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
                        setState(() { _error = e.toString().replaceAll('Exception:', '').trim(); _loading = false; });
                      }
                    }},
                    [text(_loading ? 'loading...' : 'login')]
                ),
              ]
          ),
          if (_error != null)
            p(
                classes: 'error-msg',
                attributes: const {
                  'style': 'color: #d9534f; font-size: 12px; margin-top: 8px; text-align: center;'
                },
                [text(_error!)]
            ),
          div(
              attributes: const {
                'style': 'margin-top: 20px; font-size: 11px; color: #555; text-align: center;'
              },
              [
                text('not cool yet? '),
                span(
                    attributes: const {
                      'style': 'text-decoration: underline; cursor: pointer; font-weight: bold; color: #000;'
                    },
                    events: {'click': (e) => setState(() { _isRegister = true; _error = null; })},
                    [text('register here.')]
                )
              ]
          )
        ]
    );
  }
}