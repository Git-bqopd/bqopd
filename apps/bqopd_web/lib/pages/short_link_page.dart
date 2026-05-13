import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import '../utils/web_firebase_interop.dart';

class ShortLinkPage extends StatefulComponent {
  final String code;

  const ShortLinkPage({required this.code});

  @override
  State<ShortLinkPage> createState() => _ShortLinkPageState();
}

class _ShortLinkPageState extends State<ShortLinkPage> {
  String _status = "Resolving link...";

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      // 1. Check Shortcodes collection (uppercase keys)
      final res = await fsGetDoc('shortcodes/${component.code.toUpperCase()}');
      final data = jsonDecode(res);

      if (data['exists'] == true) {
        final doc = data['data'];
        if (doc['type'] == 'fanzine') {
          Router.of(context).push('/reader/${doc['contentId']}');
          return;
        } else if (doc['type'] == 'user') {
          Router.of(context).push('/profile?userId=${doc['contentId']}');
          return;
        }
      }

      // 2. Check direct username match
      final uRes = await fsGetDoc('usernames/${component.code.toLowerCase()}');
      final uData = jsonDecode(uRes);

      if (uData['exists'] == true) {
        Router.of(context).push('/profile?userId=${uData['data']['uid']}');
        return;
      }

      // If it drops to here, link doesn't exist
      setState(() {
        _status = "Link '${component.code}' not found.";
      });

    } catch (e) {
      setState(() {
        _status = "Error resolving link: $e";
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'flex-col items-center justify-center w-full', attributes: {'style': 'min-height: 100vh;'}, [
      p(classes: 'text-lg font-bold', [text(_status)]),
      a(href: '/', [text('Go Home')])
    ]);
  }
}