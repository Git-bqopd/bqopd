import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'return_intent.dart';
import 'router_utils.dart';

ReturnIntent? _pendingIntent;

Future<T?> guardWrite<T>(BuildContext ctx, Future<T> Function() doWrite,
    {required String action, Map<String, String>? extras}) async {
  if (FirebaseAuth.instance.currentUser != null) {
    return await doWrite();
  }
  final intent = ReturnIntent(url: currentUrl(ctx), action: action, extras: extras);
  _pendingIntent = intent;
  ctx.go('/auth?return=${Uri.encodeComponent(intent.encode())}');
  return null;
}

ReturnIntent? consumePendingIntent() {
  final intent = _pendingIntent;
  _pendingIntent = null;
  return intent;
}
