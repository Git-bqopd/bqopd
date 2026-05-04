import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bqopd_ui/bqopd_ui.dart';
import 'package:bqopd_state/bqopd_state.dart';

class LoginWidget extends StatefulWidget {
  final void Function()? onTap;
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
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        // BREAK THE LOOP: Only trigger success if the user is NOT anonymous.
        // The AuthBloc emits 'authenticated' for both real and anonymous users.
        if (state.status == AuthStatus.authenticated) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null && !user.isAnonymous) {
            debugPrint("LoginWidget: Real user detected. Closing login form.");
            if (widget.onLoginSuccess != null) widget.onLoginSuccess!();
          } else {
            debugPrint("LoginWidget: Staying open (User is anonymous or null).");
          }
        } else if (state.status == AuthStatus.failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage ?? "Login failed")),
          );
        }
      },
      child: AspectRatio(
        aspectRatio: 5 / 8,
        child: Container(
          color: const Color(0xFFF1B255),
          padding: const EdgeInsets.all(10.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state.status == AuthStatus.loading;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/logo200.gif', width: 150),
                            const SizedBox(height: 25),
                            const Text('bqopd', style: TextStyle(fontSize: 20)),
                            const SizedBox(height: 30),
                            AutofillGroup(
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
                            const SizedBox(height: 25),
                            MyButton(
                              text: "login",
                              onTap: () => context.read<AuthBloc>().add(
                                LoginRequested(emailController.text.trim(), passwordController.text),
                              ),
                              isLoading: isLoading,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("not cool yet?", style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: widget.onTap,
                                  child: const Text(
                                    "register here",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            )
                          ],
                        );
                      },
                    ),
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