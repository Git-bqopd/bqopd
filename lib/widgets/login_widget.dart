import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/button.dart';
import '../components/textfield.dart';
import '../services/user_bootstrap.dart';

class LoginWidget extends StatefulWidget {
  // Callback function to trigger switching to the register page
  final void Function()? onTap;

  // NEW: Callback when login is successful (to close modals, etc.)
  final VoidCallback? onLoginSuccess;

  const LoginWidget({
    super.key,
    required this.onTap,
    this.onLoginSuccess,
  });

  @override
  State<LoginWidget> createState() => _LoginWidgetState();
}

class _LoginWidgetState extends State<LoginWidget> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FocusNode emailFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();
  bool _isLoading = false;

  void login() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      await ensureUserDocument();

      if (widget.onLoginSuccess != null) {
        widget.onLoginSuccess!();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        displayMessageToUser(e.message ?? e.code, context);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. The "Envelope" (Manilla Background)
    return Container(
      color: const Color(0xFFF1B255), // Manilla Envelope Color
      padding:
      const EdgeInsets.all(24.0), // Padding = The visible envelope edge
      child: Center(
        child: AspectRatio(
          // 2. The "Sticker" Shape (5:8)
          aspectRatio: 5 / 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white, // Sticker Color
              borderRadius:
              BorderRadius.circular(12.0), // Rounded corners for sticker
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/logo200.gif',
                        width: 100,
                        semanticLabel: 'Company Logo',
                      ),
                      const SizedBox(height: 10),
                      const Text('bqopd', style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 20),
                      Form(
                        child: AutofillGroup(
                          child: Column(
                            children: [
                              MyTextField(
                                controller: emailController,
                                focusNode: emailFocusNode,
                                hintText: "email",
                                obscureText: false,
                                autofillHints: const [AutofillHints.email],
                              ),
                              const SizedBox(height: 10),
                              MyTextField(
                                controller: passwordController,
                                focusNode: passwordFocusNode,
                                hintText: "password",
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: () {
                              displayMessageToUser(
                                  "forgot password tapped (not implemented)",
                                  context);
                            },
                            child: const Text(
                              "forgot password?",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),
                      MyButton(
                        text: "login",
                        onTap: login,
                        isLoading: _isLoading,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("not cool yet?",
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: widget.onTap,
                            child: const Text(
                              "register here",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void displayMessageToUser(String message, BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}