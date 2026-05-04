import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/login_widget.dart';
import 'package:bqopd_ui/bqopd_ui.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The LoginWidget now includes its own aspect ratio and styling wrapper
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: true,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: LoginWidget(
                onTap: () => context.go('/register'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}