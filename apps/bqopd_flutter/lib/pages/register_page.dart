import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/register_widget.dart';
import 'package:bqopd_ui/bqopd_ui.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The RegisterWidget now includes its own aspect ratio and styling wrapper
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: true,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: RegisterWidget(
                onTap: () => context.go('/login'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}