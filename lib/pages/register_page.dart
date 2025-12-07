import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/register_widget.dart';

class RegisterPage extends StatelessWidget {

  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    // This page is now exclusively dedicated to displaying the full Register form.
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: true,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                // Display the full Register Form
                child: RegisterWidget(
                  onTap: () => context.go('/login'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}