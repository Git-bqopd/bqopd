import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

Future<void> guardWrite(BuildContext ctx, Future<void> Function() doIt,
    {required String currentUrl, required String action}) async {
  if (FirebaseAuth.instance.currentUser == null) {
    final payload =
        base64Url.encode(utf8.encode('{"url":"$currentUrl","action":"$action"}'));
    if (ctx.mounted) {
      ctx.go('/auth?return=$payload');
    }
    return;
  }
  await doIt();
}
