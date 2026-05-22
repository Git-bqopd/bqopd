import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import 'stats_table.dart';

class FanzineHeader extends StatefulComponent {
  final String? fanzineId;
  final String? shortCode;
  final Map<String, dynamic>? fanzineData;
  final Map<String, Map<String, dynamic>> creatorProfiles;
  final Map<String, Map<String, dynamic>> imageStats;
  final List<Map<String, dynamic>> pageStructure;
  final bool isStickerOnly;
  final AuthState? authState;
  final AuthBloc? authBloc;

  const FanzineHeader({
    this.fanzineId,
    this.shortCode,
    this.fanzineData,
    this.creatorProfiles = const {},
    this.imageStats = const {},
    this.pageStructure = const [],
    this.isStickerOnly = false,
    this.authState,
    this.authBloc,
    super.key,
  });

  @override
  State<FanzineHeader> createState() => _FanzineHeaderState();
}

class _FanzineHeaderState extends State<FanzineHeader> {
  int _activeTab = 0; // 0: indicia, 1: creators, 2: stats
  String _displayUrl = 'login / register';
  String? _username; // Store user handle explicitly

  // Inline Login/Register states
  bool _showLogin = false;
  bool _showRegister = false;
  String _email = '';
  String _password = '';
  String _usernameInput = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveDisplayUrl();
  }

  Future<void> _resolveDisplayUrl() async {
    if (!kIsWeb) return;

    final uid = getCurrentUserId();
    if (uid == null) {
      _displayUrl = 'login / register';
      _username = null;
    } else {
      try {
        final res = await fsGetDoc('profiles/$uid');
        final data = jsonDecode(res);
        if (data['exists']) {
          final String handle = data['data']['username'] ?? 'archival';
          final resolvedUrl = 'bqopd.com/$handle';
          if (mounted) {
            setState(() {
              _displayUrl = resolvedUrl;
              _username = handle;
            });
          } else {
            _displayUrl = resolvedUrl;
            _username = handle;
          }
        }
      } catch (e) {
        print("Error resolving display URL: $e");
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final isLoggedIn = component.authState?.status == AuthStatus.authenticated;
    if (isLoggedIn) {
      _showLogin = false;
      _showRegister = false;
    }

    final navLink = button(
      classes: 'nav-pill',
      events: {
        'click': (e) {
          final uid = getCurrentUserId();
          if (uid == null) {
            setState(() {
              _showLogin = true;
              _showRegister = false;
            });
          } else {
            // Navigate directly to the resolved handle/shortlink (e.g. '/kevin')
            // instead of using the generic '/profile' path.
            if (_username != null && _username!.isNotEmpty) {
              Router.of(context).push('/$_username');
            } else {
              Router.of(context).push('/profile');
            }
          }
        }
      },
      [text(_displayUrl)],
    );

    if (component.isStickerOnly) {
      return div(classes: 'flex-col items-center w-full h-full p-2', [
        navLink,
        div(
            classes: 'flex-1 flex-col justify-center items-center w-full',
            [
              _showLogin
                  ? _buildLocalLogin()
                  : _showRegister
                  ? _buildLocalRegister()
                  : div(
                  classes: 'white-sticker',
                  [
                    img(
                      src: 'assets/logo200.gif',
                      attributes: {'style': 'width: 100px; height: auto; display: block;'},
                    )
                  ]
              )
            ]
        )
      ]);
    }

    final indiciaText = component.fanzineData?['masterIndicia'] ?? "© 2026 BQOPD Collective.";
    final creators = component.fanzineData?['masterCreators'] as List? ?? [];

    final stickerView = div(
        classes: 'fh-sticker-view flex-col items-center w-full h-full p-2',
        [
          navLink,
          div(
              classes: 'flex-1 flex-col justify-center items-center w-full',
              [
                _showLogin
                    ? _buildLocalLogin()
                    : _showRegister
                    ? _buildLocalRegister()
                    : div(
                    classes: 'white-sticker',
                    [
                      img(
                        src: 'assets/logo200.gif',
                        attributes: {'style': 'width: 100px; height: auto; display: block;'},
                      )
                    ]
                )
              ]
          )
        ]
    );

    final fullView = div(classes: 'fh-full-view flex-col items-center w-full h-full p-2', [
      navLink,
      _showLogin
          ? _buildLocalLogin()
          : _showRegister
          ? _buildLocalRegister()
          : div(classes: 'white-sticker-compact w-full mt-2', [
        div(classes: 'flex-row justify-center items-center py-2 bg-gray-100', [
          _buildTab('indicia', 0),
          span(classes: 'px-4 text-gray text-xs', [text('|')]),
          _buildTab('creators', 1),
          span(classes: 'px-4 text-gray text-xs', [text('|')]),
          _buildTab('stats', 2),
        ]),
        div(classes: 'flex-col flex-1 p-4 overflow-y-auto', [
          div(classes: _activeTab == 0 ? '' : 'hidden', [
            p(
              classes: 'text-xs text-justify',
              attributes: {'style': 'font-family: Georgia; line-height: 1.5;'},
              [text(indiciaText)],
            )
          ]),
          div(classes: _activeTab == 1 ? '' : 'hidden', [
            _buildCreatorsTab(creators),
          ]),
          div(classes: _activeTab == 2 ? '' : 'hidden', [
            if (component.fanzineId != null)
              StatsTable(
                contentId: component.fanzineId!,
                isFanzine: true,
                preloadedPages: component.pageStructure,
                preloadedStats: component.imageStats,
              )
          ])
        ])
      ])
    ]);

    return div(classes: 'w-full h-full', [
      stickerView,
      fullView,
    ]);
  }

  Component _buildLocalLogin() {
    return div(
        classes: 'white-sticker',
        attributes: {
          'style': 'padding: 24px; position: relative; display: flex; flex-direction: column; justify-content: center; align-items: center; width: 85%; height: 80%;'
        },
        [
          button(
              classes: 'close-btn',
              attributes: {
                'style': 'position: absolute; top: 12px; right: 16px; background: none; border: none; font-size: 24px; font-weight: bold; cursor: pointer; color: #555; line-height: 1; transition: color 0.15s; outline: none;'
              },
              events: {
                'click': (e) => setState(() {
                  _showLogin = false;
                  _showRegister = false;
                  _error = null;
                })
              },
              [text('×')]
          ),

          img(
              src: 'assets/logo200.gif',
              attributes: {
                'style': 'width: 80px; height: auto; display: block; margin-bottom: 8px;'
              }
          ),

          div(
              attributes: {
                'style': 'font-size: 16px; font-weight: 500; color: #222; margin-bottom: 24px; font-family: inherit; letter-spacing: 0.5px;'
              },
              [text('bqopd')]
          ),

          div(
              classes: 'flex-col w-full',
              attributes: {
                'style': 'display: flex; flex-direction: column; width: 100%; gap: 10px;'
              },
              [
                input(
                  attributes: {
                    'type': 'email',
                    'placeholder': 'email',
                    'value': _email,
                    'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                  },
                  events: {'input': (e) => _email = (e.target as dynamic).value},
                ),
                input(
                  attributes: {
                    'type': 'password',
                    'placeholder': 'password',
                    'value': _password,
                    'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                  },
                  events: {'input': (e) => _password = (e.target as dynamic).value},
                ),
                button(
                    classes: 'btn-primary',
                    attributes: {
                      'style': 'width: 100%; padding: 12px; background-color: #8e8e8e; color: white; border: none; border-radius: 8px; font-size: 14px; font-weight: bold; cursor: pointer; transition: background-color 0.2s; margin-top: 4px;'
                    },
                    events: {
                      'click': (e) async {
                        if (_email.trim().isEmpty || _password.isEmpty) {
                          setState(() => _error = "Please fill all fields.");
                          return;
                        }
                        setState(() => _loading = true);
                        try {
                          await loginWithFirebase(_email.trim(), _password);
                          setState(() { _showLogin = false; _loading = false; _error = null; });
                          _resolveDisplayUrl();
                        } catch (e) {
                          setState(() { _error = e.toString().replaceAll('Exception:', '').trim(); _loading = false; });
                        }
                      }
                    },
                    [text(_loading ? 'loading...' : 'login')]
                ),
              ]
          ),

          if (_error != null)
            p(
                classes: 'error-msg',
                attributes: {
                  'style': 'color: #d9534f; font-size: 12px; margin-top: 8px; text-align: center;'
                },
                [text(_error!)]
            ),

          div(
              attributes: {
                'style': 'margin-top: 24px; font-size: 11px; color: #555; text-align: center;'
              },
              [
                text('not cool yet? '),
                span(
                    attributes: {
                      'style': 'text-decoration: underline; cursor: pointer; font-weight: bold; color: #000;'
                    },
                    events: {
                      'click': (e) => setState(() {
                        _showLogin = false;
                        _showRegister = true;
                        _error = null;
                      })
                    },
                    [text('register here.')]
                )
              ]
          )
        ]
    );
  }

  Component _buildLocalRegister() {
    return div(
        classes: 'white-sticker',
        attributes: {
          'style': 'padding: 24px; position: relative; display: flex; flex-direction: column; justify-content: center; align-items: center; width: 85%; height: 80%;'
        },
        [
          button(
              classes: 'close-btn',
              attributes: {
                'style': 'position: absolute; top: 12px; right: 16px; background: none; border: none; font-size: 24px; font-weight: bold; cursor: pointer; color: #555; line-height: 1; transition: color 0.15s; outline: none;'
              },
              events: {
                'click': (e) => setState(() {
                  _showLogin = false;
                  _showRegister = false;
                  _error = null;
                })
              },
              [text('×')]
          ),

          img(
              src: 'assets/logo200.gif',
              attributes: {
                'style': 'width: 80px; height: auto; display: block; margin-bottom: 8px;'
              }
          ),

          div(
              attributes: {
                'style': 'font-size: 16px; font-weight: 500; color: #222; margin-bottom: 24px; font-family: inherit; letter-spacing: 0.5px;'
              },
              [text('bqopd')]
          ),

          div(
              classes: 'flex-col w-full',
              attributes: {
                'style': 'display: flex; flex-direction: column; width: 100%; gap: 10px;'
              },
              [
                input(
                  attributes: {
                    'type': 'text',
                    'placeholder': 'username',
                    'value': _usernameInput,
                    'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                  },
                  events: {'input': (e) => _usernameInput = (e.target as dynamic).value},
                ),
                input(
                  attributes: {
                    'type': 'email',
                    'placeholder': 'email',
                    'value': _email,
                    'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                  },
                  events: {'input': (e) => _email = (e.target as dynamic).value},
                ),
                input(
                  attributes: {
                    'type': 'password',
                    'placeholder': 'password',
                    'value': _password,
                    'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
                  },
                  events: {'input': (e) => _password = (e.target as dynamic).value},
                ),
                button(
                    classes: 'btn-primary',
                    attributes: {
                      'style': 'width: 100%; padding: 12px; background-color: #8e8e8e; color: white; border: none; border-radius: 8px; font-size: 14px; font-weight: bold; cursor: pointer; transition: background-color 0.2s; margin-top: 4px;'
                    },
                    events: {
                      'click': (e) async {
                        if (_usernameInput.trim().isEmpty || _email.trim().isEmpty || _password.isEmpty) {
                          setState(() => _error = "Please fill all fields.");
                          return;
                        }
                        setState(() => _loading = true);
                        try {
                          await registerWithFirebase(_email.trim(), _password, _usernameInput.trim());
                          setState(() { _showRegister = false; _loading = false; _error = null; });
                          _resolveDisplayUrl();
                        } catch (e) {
                          setState(() { _error = e.toString().replaceAll('Exception:', '').trim(); _loading = false; });
                        }
                      }
                    },
                    [text(_loading ? 'loading...' : 'register')]
                ),
              ]
          ),

          if (_error != null)
            p(
                classes: 'error-msg',
                attributes: {
                  'style': 'color: #d9534f; font-size: 12px; margin-top: 8px; text-align: center;'
                },
                [text(_error!)]
            ),

          div(
              attributes: {
                'style': 'margin-top: 24px; font-size: 11px; color: #555; text-align: center;'
              },
              [
                text('already cool? '),
                span(
                    attributes: {
                      'style': 'text-decoration: underline; cursor: pointer; font-weight: bold; color: #000;'
                    },
                    events: {
                      'click': (e) => setState(() {
                        _showRegister = false;
                        _showLogin = true;
                        _error = null;
                      })
                    },
                    [text('login here.')]
                )
              ]
          )
        ]
    );
  }

  Component _buildTab(String label, int index) {
    final isActive = _activeTab == index;
    return span(
      classes: 'text-xs cursor-pointer ${isActive ? 'font-bold' : 'text-gray'}',
      events: {'click': (e) => setState(() => _activeTab = index)},
      [text(label)],
    );
  }

  Component _buildCreatorsTab(List creators) {
    if (creators.isEmpty) return p(classes: 'text-xs text-center text-gray', [text('No creators listed.')]);

    return div(classes: 'creator-list', [
      div(attributes: {'style': 'display: inline-flex; flex-direction: column; align-items: flex-start;'}, [
        for (var c in creators)
          div(
            classes: 'creator-row',
            attributes: {'style': 'width: auto;'},
            [
              span(classes: 'creator-role', [text('${c['role']}')]),
              span(classes: 'creator-divider', [text('|')]),
              div(classes: 'creator-identity', [
                UserTile(
                  profile: component.creatorProfiles[c['uid']],
                  fallbackName: c['name'] ?? 'Unknown',
                ),
              ]),
            ],
          )
      ])
    ]);
  }
}

class UserTile extends StatelessComponent {
  final Map<String, dynamic>? profile;
  final String fallbackName;

  const UserTile({this.profile, required this.fallbackName, super.key});

  @override
  Component build(BuildContext context) {
    final String displayName = profile?['displayName'] ?? fallbackName;
    final String? username = profile?['username'];
    final String? photoUrl = profile?['photoUrl'];

    return div(classes: 'user-tile', [
      div(classes: 'user-avatar-container', [
        if (photoUrl != null && photoUrl.isNotEmpty)
          img(classes: 'user-avatar', src: photoUrl)
        else
          div(classes: 'user-avatar-placeholder', [text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')])
      ]),
      div(classes: 'user-info', [
        div(classes: 'user-display-name', [text(displayName)]),
        if (username != null) div(classes: 'user-handle', [text('@$username')])
      ])
    ]);
  }
}