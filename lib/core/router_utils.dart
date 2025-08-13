import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

String currentUrl(BuildContext context) {
  return GoRouter.of(context).location;
}
