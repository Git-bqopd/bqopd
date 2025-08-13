import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

String currentUrl(BuildContext context) {
  // Use GoRouterState to read the active URL (path + query).
  // Works for widgets built under a GoRoute builder.
  return GoRouterState.of(context).uri.toString();
}
