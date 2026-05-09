import 'package:flutter/material.dart';
import 'login_widget.dart';
import 'register_widget.dart';

class AuthModal extends StatefulWidget {
  final VoidCallback? onSuccess;

  const AuthModal({super.key, this.onSuccess});

  @override
  State<AuthModal> createState() => _AuthModalState();
}

class _AuthModalState extends State<AuthModal> {
  bool _isLogin = true;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Stack(
          children: [
            _isLogin
                ? LoginWidget(
              onTap: () => setState(() => _isLogin = false),
              onLoginSuccess: () {
                if (widget.onSuccess != null) widget.onSuccess!();
                Navigator.of(context).pop();
              },
            )
                : RegisterWidget(
              onTap: () => setState(() => _isLogin = true),
              onRegisterSuccess: () {
                if (widget.onSuccess != null) widget.onSuccess!();
                Navigator.of(context).pop();
              },
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Material(
                color: Colors.white.withValues(alpha: 0.8),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: "Cancel",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}