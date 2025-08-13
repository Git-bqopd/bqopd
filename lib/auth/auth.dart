import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'login_or_register.dart';
import '../pages/fanzine_page.dart';

class AuthPage extends StatelessWidget {
  final String? returnParam; // e.g., '/Ab3XyZ1'
  final String? mode;        // optional: 'login' | 'register'
  const AuthPage({super.key, this.returnParam, this.mode});

  @override
  Widget build(BuildContext context) {
    // Also read query from the live URL in case args weren't provided
    final qp = GoRouterState.of(context).uri.queryParameters;
    final desiredReturn = returnParam ?? qp['return'];

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Not logged in → show your existing combined login/register UI
        if (snap.data == null) {
          return const Scaffold(
            body: LoginOrRegister(),
          );
        }

        // Logged in → bounce back to the original URL (if provided)
        if (desiredReturn != null && desiredReturn.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final currentUrl = GoRouterState.of(context).uri.toString();
            if (currentUrl != desiredReturn) {
              context.go(desiredReturn);
            }
          });
          return const SizedBox.shrink();
        }

        // Fallback after auth: land on your app home
        return const FanzinePage();
      },
    );
  }
}
