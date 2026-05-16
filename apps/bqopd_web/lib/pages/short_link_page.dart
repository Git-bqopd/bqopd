import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import 'fanzine_reader_page.dart';
import 'profile_page.dart';

class ShortLinkPage extends StatefulComponent {
  final String code;
  final String? pageNumber; // NEW: Immutable path variable for deep linking
  final AuthState? authState;
  final AuthBloc? authBloc;

  const ShortLinkPage({
    required this.code,
    this.pageNumber,
    this.authState,
    this.authBloc,
  });

  @override
  State<ShortLinkPage> createState() => _ShortLinkPageState();
}

class _ShortLinkPageState extends State<ShortLinkPage> {
  String _status = "Resolving link...";
  String? _targetFanzineId;
  String? _targetUserId;
  bool _isResolved = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateComponent(ShortLinkPage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.code != component.code) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    setState(() {
      _status = "Resolving link...";
      _targetFanzineId = null;
      _targetUserId = null;
      _isResolved = false;
    });

    try {
      final String code = component.code;

      final res = await fsGetDoc('shortcodes/${code.toUpperCase()}');
      final data = jsonDecode(res);

      if (data['exists'] == true) {
        final doc = data['data'];
        if (doc['type'] == 'fanzine') {
          setState(() {
            _targetFanzineId = doc['contentId'];
            _isResolved = true;
          });
          return;
        } else if (doc['type'] == 'user') {
          setState(() {
            _targetUserId = doc['contentId'];
            _isResolved = true;
          });
          return;
        }
      }

      final uRes = await fsGetDoc('usernames/${code.toLowerCase()}');
      final uData = jsonDecode(uRes);

      if (uData['exists'] == true) {
        setState(() {
          _targetUserId = uData['data']['uid'];
          _isResolved = true;
        });
        return;
      }

      final fzRes = await fsQuery('fanzines', 'shortCode', '==', jsonEncode(code), '');
      final fzDocs = jsonDecode(fzRes) as List;

      if (fzDocs.isNotEmpty) {
        setState(() {
          _targetFanzineId = fzDocs.first['id'];
          _isResolved = true;
        });
        return;
      }

      final pRes = await fsQuery('profiles', 'username', '==', jsonEncode(code.toLowerCase()), '');
      final pDocs = jsonDecode(pRes) as List;

      if (pDocs.isNotEmpty) {
        setState(() {
          _targetUserId = pDocs.first['id'];
          _isResolved = true;
        });
        return;
      }

      setState(() {
        _status = "Link '${component.code}' not found.";
        _isResolved = true;
      });

    } catch (e) {
      setState(() {
        _status = "Error resolving link: $e";
        _isResolved = true;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    if (!_isResolved) {
      return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
        div(classes: 'text-lg font-bold', [text(_status)])
      ]);
    }

    if (_targetFanzineId != null) {
      // Convert path string to integer for initialization
      final initialPage = component.pageNumber != null ? int.tryParse(component.pageNumber!) : null;

      return FanzineReaderPage(
        fanzineId: _targetFanzineId!,
        initialPageNumber: initialPage,
      );
    }

    if (_targetUserId != null && component.authBloc != null) {
      return ProfilePage(authState: component.authState, authBloc: component.authBloc!);
    }

    return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
      p(classes: 'text-lg font-bold', [text(_status)]),
      a(href: '/', [text('Go Home')])
    ]);
  }
}