import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/return_intent.dart';
import '../widgets/login_widget.dart';
import '../widgets/register_widget.dart';

class AuthPage extends StatefulWidget {
  final String returnParam;
  final String? mode;
  const AuthPage({super.key, required this.returnParam, this.mode});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late bool _showLogin;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _showLogin = widget.mode != 'register';
  }

  void _toggle() {
    setState(() {
      _showLogin = !_showLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.data != null && !_handled) {
            _handled = true;
            final intent = ReturnIntent.decode(widget.returnParam);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.go(intent.url);
            });
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _showLogin = true),
                    child: const Text('Login'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showLogin = false),
                    child: const Text('Register'),
                  ),
                ],
              ),
              Expanded(
                child: _showLogin
                    ? LoginWidget(onTap: _toggle)
                    : RegisterWidget(onTap: _toggle),
              ),
            ],
          );
        },
      ),
    );
  }
}
