import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/button.dart';
import '../components/textfield.dart';

class RegisterWidget extends StatefulWidget {
  // Callback function to toggle back to the login page
  final void Function()? onTap;

  const RegisterWidget({super.key, required this.onTap});

  @override
  State<RegisterWidget> createState() => _RegisterWidgetState();
}

class _RegisterWidgetState extends State<RegisterWidget> {
  // Text editing controllers
  final TextEditingController userNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController pwController = TextEditingController();
  final TextEditingController confirmPwController = TextEditingController();

  @override
  void dispose() {
    // Dispose controllers when the widget is removed
    userNameController.dispose();
    emailController.dispose();
    pwController.dispose();
    confirmPwController.dispose();
    super.dispose();
  }

  // --- Register User Method ---
  void registerUser() async {
    // Show loading circle
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Check password match
    if (pwController.text != confirmPwController.text) {
      if (mounted) Navigator.pop(context); // Pop loading dialog
      displayMessageToUser("Passwords don't match!", context);
      return;
    }

    // Try creating user
    try {
      UserCredential? userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: pwController.text,
      );

      // Create Firestore document
      await createUserDocument(userCredential);

      // Pop loading circle on success
      if (mounted) Navigator.pop(context);

    } on FirebaseAuthException catch (e) {
      // Pop loading circle on error
      if (mounted) Navigator.pop(context);
      // Display error
      if (mounted) displayMessageToUser(e.message ?? e.code, context);
    }
  }

  // --- Create User Document Method ---
  Future<void> createUserDocument(UserCredential? userCredential) async {
    if (userCredential?.user?.email != null) {
      final usersCollection = FirebaseFirestore.instance.collection('Users');
      await usersCollection.doc(userCredential!.user!.email).set({
        'email': userCredential.user!.email,
        'username': userNameController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      print("Error: User credential or user email was null. Document not created.");
    }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // Wrap the content with a Container to set the background color
    return Container(
      color: const Color(0xFFF1B255), // Set the default background color
      // Use ClipRRect to ensure content respects potential rounded corners
      // from the parent container in RegisterPage.
      child: ClipRRect(
        // If you want rounded corners on the yellow background itself:
        // borderRadius: BorderRadius.circular(12.0), // Example
        child: Center( // Center the scrollable content
          child: SingleChildScrollView( // Allow scrolling
            child: Padding(
              padding: const EdgeInsets.all(25.0), // Inner padding
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // logo
                  Image.asset(
                    'assets/logo200.gif',
                    width: 150,
                  ),
                  const SizedBox(height: 25),

                  // slogan
                  const Text('bqopd', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 50),

                  // Username Text Field
                  MyTextField(
                    controller: userNameController,
                    hintText: "Username",
                    obscureText: false,
                  ),
                  const SizedBox(height: 10),

                  // Email Text Field
                  MyTextField(
                    controller: emailController,
                    hintText: "Email",
                    obscureText: false,
                  ),
                  const SizedBox(height: 10),

                  // Password Text Field
                  MyTextField(
                    controller: pwController,
                    hintText: "Password",
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),

                  // Confirm Password Text Field
                  MyTextField(
                    controller: confirmPwController,
                    hintText: "Confirm Password",
                    obscureText: true,
                  ),
                  const SizedBox(height: 25),

                  // Register Button (Consider adding loading state here too)
                  MyButton(
                    text: "Register",
                    onTap: registerUser,
                  ),
                  const SizedBox(height: 25),

                  // Already have an account? Login here link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Already cool?"),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: widget.onTap, // Use the passed-in callback
                        child: Text(
                          "Login here",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColorDark,
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
    );
  }
}

// Ensure displayMessageToUser helper function is defined and imported correctly
void displayMessageToUser(String message, BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
