import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_utils.dart';
import '../../utils/web_firebase_interop.dart';

/// Persistent 50px header bar pinned to `top: 0` in Column 2 (`#fanzine-list-area`).
/// Appears when the FanzineReader envelope scrolls out of the visible viewport,
/// maintaining the visual illusion that the bottom 50px of the card remained behind.
class FanzineListStickyHeader extends StatefulComponent {
  final String title;
  final String? shortCode;
  final bool isColumn1Open;
  final AuthState? authState;
  final AuthBloc? authBloc;
  final VoidCallback? onTitleTap;

  const FanzineListStickyHeader({
    required this.title,
    this.shortCode,
    this.isColumn1Open = false,
    this.authState,
    this.authBloc,
    this.onTitleTap,
    super.key,
  });

  @override
  State<FanzineListStickyHeader> createState() => _FanzineListStickyHeaderState();
}

class _FanzineListStickyHeaderState extends State<FanzineListStickyHeader> {
  String _displayUrl = 'login / register';
  String? _username;
  bool _isScrolled = false;
  web.Element? _listElement;
  JSFunction? _scrollHandler;

  @override
  void initState() {
    super.initState();
    _resolveDisplayUrl();
    if (kIsWeb) {
      Future.microtask(() => _attachScrollListener());
    }
  }

  @override
  void didUpdateComponent(FanzineListStickyHeader oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.authState != component.authState) {
      _resolveDisplayUrl();
    }
  }

  @override
  void dispose() {
    if (_listElement != null && _scrollHandler != null) {
      _listElement!.removeEventListener('scroll', _scrollHandler!);
      _scrollHandler = null;
      _listElement = null;
    }
    super.dispose();
  }

  void _attachScrollListener([int retries = 5]) {
    if (!kIsWeb || !mounted) return;
    final listEl = web.document.getElementById('fanzine-list-area');
    if (listEl != null) {
      _listElement = listEl;

      void checkScroll() {
        final headerEl = web.document.getElementById('fanzine-header');
        // Measures bounding rectangle height directly from Element to avoid platform type-cast issues
        final double headerHeight = headerEl != null
            ? headerEl.getBoundingClientRect().height.toDouble()
            : 430.0;
        final double threshold = (headerHeight - 50.0).clamp(0.0, double.infinity);
        final bool isNowScrolled = listEl.scrollTop >= threshold;
        if (isNowScrolled != _isScrolled && mounted) {
          setState(() => _isScrolled = isNowScrolled);
        }
      }

      final handler = ((web.Event e) {
        checkScroll();
      }).toJS;
      _scrollHandler = handler;
      listEl.addEventListener('scroll', handler);
      checkScroll();
    } else if (retries > 0) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _attachScrollListener(retries - 1);
      });
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
        print('[FanzineListStickyHeader] Error resolving display URL: $e');
      }
    }
  }

  @override
  Component build(BuildContext context) {
    if (!_isScrolled) {
      return div(
        classes: 'list-sticky-header hidden',
        attributes: const {'style': 'display: none !important;'},
        [],
      );
    }

    final urlPill = button(
      classes: 'nav-pill',
      attributes: const {'style': 'margin-bottom: 0; white-space: nowrap;'},
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

    final titleText = component.title.isNotEmpty ? component.title : 'fanzine';
    final titlePill = button(
      classes: 'nav-pill title-pill',
      attributes: {
        'style':
        "margin-bottom: 0; max-width: ${component.isColumn1Open ? '320px' : '220px'}; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 700;",
        'title': titleText,
      },
      events: {
        'click': (e) {
          if (component.onTitleTap != null) {
            component.onTitleTap!();
          } else {
            scrollContainerToTop('fanzine-list-area', smooth: true);
          }
        }
      },
      [Component.text(titleText)],
    );

    return div(
      classes: 'list-sticky-header',
      attributes: const {
        'style':
        'position: sticky; top: 0; z-index: 30; width: 100%; height: 50px; min-height: 50px; max-height: 50px; background-color: var(--envelope-yellow, #F1B255); display: flex; align-items: center; justify-content: center; box-sizing: border-box; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.18);'
      },
      [
        div(
          classes: 'flex-row items-center justify-center gap-2 px-4 w-full h-full',
          [
            if (component.isColumn1Open)
              span(classes: 'hidden-on-desktop flex-row items-center', [urlPill])
            else
              urlPill,
            titlePill,
          ],
        )
      ],
    );
  }
}