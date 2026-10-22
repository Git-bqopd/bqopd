import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_utils.dart';
import '../utils/web_firebase_interop.dart';

/// The pinned header sliver bar that pops up at the top of Column 1 (`#fanzine-grid-area`).
/// Remains completely hidden (`display: none`) while at the top of the publication,
/// and pops up instantly (no animation) with the navigation pill the moment the top
/// of FanzineHeader touches the top of the visible column (`scrollTop > 20`).
class FanzineStickyHeader extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc? authBloc;

  const FanzineStickyHeader({
    this.authState,
    this.authBloc,
    super.key,
  });

  @override
  State<FanzineStickyHeader> createState() => _FanzineStickyHeaderState();
}

class _FanzineStickyHeaderState extends State<FanzineStickyHeader> {
  String _displayUrl = 'login / register';
  String? _username;
  bool _isScrolled = false;
  web.Element? _gridElement;
  JSFunction? _scrollHandler;

  @override
  void initState() {
    super.initState();
    _resolveDisplayUrl();
    if (kIsWeb) {
      Future.microtask(() => _attachScrollListener());
    }
  }

  void _attachScrollListener([int retries = 5]) {
    if (!kIsWeb || !mounted) return;
    final gridEl = web.document.getElementById('fanzine-grid-area');
    if (gridEl != null) {
      _gridElement = gridEl;

      void checkScroll() {
        // Appears the moment FanzineHeader on Spread 0 touches the top of the visible column
        final bool isNowScrolled = gridEl.scrollTop > 20;
        if (isNowScrolled != _isScrolled && mounted) {
          setState(() => _isScrolled = isNowScrolled);
        }
      }

      final handler = ((web.Event e) {
        checkScroll();
      }).toJS;
      _scrollHandler = handler;
      gridEl.addEventListener('scroll', handler);
      // Run once immediately on mount to establish state
      checkScroll();
    } else if (retries > 0) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _attachScrollListener(retries - 1);
      });
    }
  }

  @override
  void didUpdateComponent(FanzineStickyHeader oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.authState != component.authState) {
      _resolveDisplayUrl();
    }
  }

  @override
  void dispose() {
    if (_gridElement != null && _scrollHandler != null) {
      _gridElement!.removeEventListener('scroll', _scrollHandler!);
      _scrollHandler = null;
      _gridElement = null;
    }
    super.dispose();
  }

  Future<void> _resolveDisplayUrl() async {
    if (!kIsWeb) return;
    final uid = getCurrentUserId();
    if (uid == null) {
      if (mounted) {
        setState(() {
          _displayUrl = 'login / register';
          _username = null;
        });
      } else {
        _displayUrl = 'login / register';
        _username = null;
      }
    } else {
      try {
        final res = await fsGetDoc('profiles/$uid');
        final data = jsonDecode(res);
        if (data['exists'] == true) {
          final String handle = data['data']['username'] ?? 'archival';
          final resolvedUrl = 'bqopd.com/@$handle';
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
        print("Error resolving sticky display URL: $e");
      }
    }
  }

  @override
  Component build(BuildContext context) {
    // If not scrolled off, keep completely hidden with no footprint
    if (!_isScrolled) {
      return div(
        classes: 'grid-sticky-header hidden',
        attributes: const {'style': 'display: none !important;'},
        [],
      );
    }

    final navLink = button(
      classes: 'nav-pill',
      attributes: const {'style': 'margin-bottom: 0;'},
      events: {
        'click': (e) {
          final uid = getCurrentUserId();
          if (uid == null) {
            GlobalModalBus.show();
          } else {
            if (_username != null && _username!.isNotEmpty) {
              Router.of(context).push('/@$_username');
            } else {
              Router.of(context).push('/profile');
            }
          }
        }
      },
      [Component.text(_displayUrl)],
    );

    return div(
      classes: 'grid-sticky-header',
      [navLink],
    );
  }
}

/// The dedicated Column 1 (Grid View Spread) cover card envelope.
/// Displays the navigation pill and white logo sticker (or inline login/register forms) on Spread 0.
class FanzineHeader extends StatefulComponent {
  final AuthState? authState;
  final AuthBloc? authBloc;
  final bool showNavPill;

  const FanzineHeader({
    this.authState,
    this.authBloc,
    this.showNavPill = true,
    // Optional legacy parameters accepted for backwards compatibility
    String? fanzineId,
    String? shortCode,
    Map<String, dynamic>? fanzineData,
    Map<String, Map<String, dynamic>> creatorProfiles = const {},
    Map<String, Map<String, dynamic>> imageStats = const {},
    List<Map<String, dynamic>> pageStructure = const [],
    bool isStickerOnly = true,
    super.key,
  });

  @override
  State<FanzineHeader> createState() => _FanzineHeaderState();
}

class _FanzineHeaderState extends State<FanzineHeader> {
  String _displayUrl = 'login / register';
  String? _username;

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

  @override
  void didUpdateComponent(FanzineHeader oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.authState != component.authState) {
      _resolveDisplayUrl();
    }
  }

  Future<void> _resolveDisplayUrl() async {
    if (!kIsWeb) return;
    final uid = getCurrentUserId();
    if (uid == null) {
      if (mounted) {
        setState(() {
          _displayUrl = 'login / register';
          _username = null;
        });
      } else {
        _displayUrl = 'login / register';
        _username = null;
      }
    } else {
      try {
        final res = await fsGetDoc('profiles/$uid');
        final data = jsonDecode(res);
        if (data['exists'] == true) {
          final String handle = data['data']['username'] ?? 'archival';
          final resolvedUrl = 'bqopd.com/@$handle';
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
              _error = null;
            });
          } else {
            if (_username != null && _username!.isNotEmpty) {
              Router.of(context).push('/@$_username');
            } else {
              Router.of(context).push('/profile');
            }
          }
        }
      },
      [Component.text(_displayUrl)],
    );

    return div(classes: 'flex-col items-center w-full h-full p-2', [
      if (component.showNavPill) navLink,
      div(
        classes: 'flex-1 flex-col justify-center items-center w-full',
        [
          if (_showLogin)
            _buildLocalLogin()
          else if (_showRegister)
            _buildLocalRegister()
          else
            div(
              classes: 'white-sticker',
              [
                img(
                  src: 'assets/logo200.gif',
                  attributes: {'style': 'width: 100px; height: auto; display: block;'},
                )
              ],
            )
        ],
      )
    ]);
  }

  Component _buildLocalLogin() {
    return div(
      key: const ValueKey('sticker_login'),
      classes: 'white-sticker',
      attributes: const {
        'style': 'padding: 24px; position: relative; display: flex; flex-direction: column; justify-content: center; align-items: center; width: 85%; height: 80%;'
      },
      [
        button(
          classes: 'close-btn',
          attributes: const {
            'style': 'position: absolute; top: 12px; right: 16px; background: none; border: none; font-size: 24px; font-weight: bold; cursor: pointer; color: #555; line-height: 1; transition: color 0.15s; outline: none;'
          },
          events: {
            'click': (e) => setState(() {
              _showLogin = false;
              _showRegister = false;
              _error = null;
            })
          },
          [Component.text('×')],
        ),
        img(
          src: 'assets/logo200.gif',
          attributes: const {
            'style': 'width: 80px; height: auto; display: block; margin-bottom: 8px;'
          },
        ),
        div(
          attributes: const {
            'style': 'font-size: 16px; font-weight: 500; color: #222; margin-bottom: 24px; font-family: inherit; letter-spacing: 0.5px;'
          },
          [Component.text('bqopd')],
        ),
        div(
          classes: 'flex-col w-full',
          attributes: const {
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
              events: {'input': (e) => _email = getInputValue(e)},
            ),
            input(
              attributes: {
                'type': 'password',
                'placeholder': 'password',
                'value': _password,
                'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
              },
              events: {'input': (e) => _password = getInputValue(e)},
            ),
            button(
              classes: 'btn-primary',
              attributes: const {
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
                    setState(() {
                      _showLogin = false;
                      _loading = false;
                      _error = null;
                    });
                    _resolveDisplayUrl();
                  } catch (e) {
                    setState(() {
                      _error = e.toString().replaceAll('Exception:', '').trim();
                      _loading = false;
                    });
                  }
                }
              },
              [Component.text(_loading ? 'loading...' : 'login')],
            ),
          ],
        ),
        if (_error != null)
          p(
            classes: 'error-msg',
            attributes: const {
              'style': 'color: #d9534f; font-size: 12px; margin-top: 8px; text-align: center;'
            },
            [Component.text(_error!)],
          ),
        div(
          attributes: const {
            'style': 'margin-top: 24px; font-size: 11px; color: #555; text-align: center;'
          },
          [
            Component.text('not cool yet? '),
            span(
              attributes: const {
                'style': 'text-decoration: underline; cursor: pointer; font-weight: bold; color: #000;'
              },
              events: {
                'click': (e) => setState(() {
                  _showLogin = false;
                  _showRegister = true;
                  _error = null;
                })
              },
              [Component.text('register here.')],
            )
          ],
        )
      ],
    );
  }

  Component _buildLocalRegister() {
    return div(
      key: const ValueKey('sticker_register'),
      classes: 'white-sticker',
      attributes: const {
        'style': 'padding: 24px; position: relative; display: flex; flex-direction: column; justify-content: center; align-items: center; width: 85%; height: 80%;'
      },
      [
        button(
          classes: 'close-btn',
          attributes: const {
            'style': 'position: absolute; top: 12px; right: 16px; background: none; border: none; font-size: 24px; font-weight: bold; cursor: pointer; color: #555; line-height: 1; transition: color 0.15s; outline: none;'
          },
          events: {
            'click': (e) => setState(() {
              _showLogin = false;
              _showRegister = false;
              _error = null;
            })
          },
          [Component.text('×')],
        ),
        img(
          src: 'assets/logo200.gif',
          attributes: const {
            'style': 'width: 80px; height: auto; display: block; margin-bottom: 8px;'
          },
        ),
        div(
          attributes: const {
            'style': 'font-size: 16px; font-weight: 500; color: #222; margin-bottom: 24px; font-family: inherit; letter-spacing: 0.5px;'
          },
          [Component.text('bqopd')],
        ),
        div(
          classes: 'flex-col w-full',
          attributes: const {
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
              events: {'input': (e) => _usernameInput = getInputValue(e)},
            ),
            input(
              attributes: {
                'type': 'email',
                'placeholder': 'email',
                'value': _email,
                'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
              },
              events: {'input': (e) => _email = getInputValue(e)},
            ),
            input(
              attributes: {
                'type': 'password',
                'placeholder': 'password',
                'value': _password,
                'style': 'width: 100%; padding: 10px 14px; border: 1px solid #ccc; border-radius: 8px; font-size: 14px; box-sizing: border-box; margin: 0; outline: none; background: white;'
              },
              events: {'input': (e) => _password = getInputValue(e)},
            ),
            button(
              classes: 'btn-primary',
              attributes: const {
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
                    setState(() {
                      _showRegister = false;
                      _loading = false;
                      _error = null;
                    });
                    _resolveDisplayUrl();
                  } catch (e) {
                    setState(() {
                      _error = e.toString().replaceAll('Exception:', '').trim();
                      _loading = false;
                    });
                  }
                }
              },
              [Component.text(_loading ? 'loading...' : 'register')],
            ),
          ],
        ),
        if (_error != null)
          p(
            classes: 'error-msg',
            attributes: const {
              'style': 'color: #d9534f; font-size: 12px; margin-top: 8px; text-align: center;'
            },
            [Component.text(_error!)],
          ),
        div(
          attributes: const {
            'style': 'margin-top: 24px; font-size: 11px; color: #555; text-align: center;'
          },
          [
            Component.text('already cool? '),
            span(
              attributes: const {
                'style': 'text-decoration: underline; cursor: pointer; font-weight: bold; color: #000;'
              },
              events: {
                'click': (e) => setState(() {
                  _showRegister = false;
                  _showLogin = true;
                  _error = null;
                })
              },
              [Component.text('login here.')],
            )
          ],
        )
      ],
    );
  }
}

/// Backwards-compatible alias for the cover card component
typedef FanzineCoverSticker = FanzineHeader;