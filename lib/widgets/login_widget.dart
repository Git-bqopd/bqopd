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
  // Controllers for email and password text fields
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  // State variable to track loading status for login button
  bool _isLoading = false;

  // --- Login Method ---
  void login() async {
    // Prevent multiple login attempts while one is in progress
    if (_isLoading) return;

    // Update UI to show loading indicator
    setState(() { _isLoading = true; });
    // Hide keyboard
    FocusScope.of(context).unfocus();

    try {
      // Attempt Firebase sign-in
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(), // Trim whitespace from email
        password: passwordController.text,
      );
      await ensureUserDocument();

      // Login successful!
      // If a success callback was provided (e.g. to close a modal), call it now.
      if (widget.onLoginSuccess != null) {
        widget.onLoginSuccess!();
      }

    } on FirebaseAuthException catch (e) {
      // Handle Firebase authentication errors
      if (mounted) {
        displayMessageToUser(e.message ?? e.code, context); // Show user-friendly message
      }
    } finally {
      // Ensure loading indicator is turned off
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // --- Dispose Method ---
  @override
  void dispose() {
    // Clean up controllers
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // Wrap the content with a Container to set the background color
    return Container(
      color: const Color(0xFFF1B255), // Default background color
      child: ClipRRect(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(15.0), // Padding inside the yellow box
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // Center content vertically
              mainAxisSize: MainAxisSize.min, // Take minimum vertical space
              children: [
                // Logo Image (adjust size as needed)
                Image.asset(
                  'assets/logo200.gif', // Ensure this asset exists
                  width: 100, // Adjust size if needed
                  semanticLabel: 'Company Logo',
                ),
                const SizedBox(height: 10),

                // Slogan Text
                const Text('bqopd', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 20),

                // Email Text Field
                MyTextField(
                  controller: emailController,
                  hintText: "Email",
                  obscureText: false,
                ),
                const SizedBox(height: 10),

                // Password Text Field
                MyTextField(
                  controller: passwordController,
                  hintText: "Password",
                  obscureText: true,
                ),
                const SizedBox(height: 10),

                // Forgot Password Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () {
                        print("Forgot password tapped!");
                        displayMessageToUser("Forgot Password Tapped (Not Implemented)", context);
                      },
                      child: const Text(
                        "Forgot password?",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Login Button (or Loading Indicator)
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : MyButton(text: "Login", onTap: login),
                const SizedBox(height: 15),

                // Register Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Not cool yet?", style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: widget.onTap, // Call the toggle function
                      child: Text(
                        "Register here",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Theme.of(context).primaryColorDark, // Example color
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
    );
  }
}

// Helper function (ensure implementation exists)
void displayMessageToUser(String message, BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}