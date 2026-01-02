import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/button.dart';
import '../components/textfield.dart';

class RegisterWidget extends StatefulWidget {
  final void Function()? onTap;

  const RegisterWidget({super.key, required this.onTap});

  @override
  State<RegisterWidget> createState() => _RegisterWidgetState();
}

class _RegisterWidgetState extends State<RegisterWidget> {
  final TextEditingController userNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController pwController = TextEditingController();
  final TextEditingController confirmPwController = TextEditingController();

  bool _isLoading = false;

  final FocusNode userNameFocusNode = FocusNode();
  final FocusNode emailFocusNode = FocusNode();
  final FocusNode pwFocusNode = FocusNode();
  final FocusNode confirmPwFocusNode = FocusNode();

  @override
  void dispose() {
    userNameController.dispose();
    emailController.dispose();
    pwController.dispose();
    confirmPwController.dispose();
    userNameFocusNode.dispose();
    emailFocusNode.dispose();
    pwFocusNode.dispose();
    confirmPwFocusNode.dispose();
    super.dispose();
  }

  void registerUser() async {
    if (_isLoading) return;

    if (pwController.text != confirmPwController.text) {
      displayMessageToUser("Passwords don't match!", context);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential? userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: pwController.text,
      );

      await createUserDocument(userCredential);
    } on FirebaseAuthException catch (e) {
      if (mounted) displayMessageToUser(e.message ?? e.code, context);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> createUserDocument(UserCredential? userCredential) async {
    if (userCredential?.user != null) {
      final user = userCredential!.user!;
      final usersCollection = FirebaseFirestore.instance.collection('Users');

      // CHANGE: Use UID as document ID
      await usersCollection.doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'username': userNameController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'Editor': false,
        'bio': '',
        'firstName': '',
        'lastName': '',
      });
    } else {
      debugPrint(
          "Error: User credential or user was null. Document not created.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1B255),
      child: ClipRRect(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo200.gif', width: 150),
                  const SizedBox(height: 25),
                  const Text('bqopd', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 50),
                  Form(
                    child: AutofillGroup(
                      child: Column(
                        children: [
                          MyTextField(
                            controller: userNameController,
                            focusNode: userNameFocusNode,
                            hintText: "Username",
                            obscureText: false,
                            autofillHints: const [AutofillHints.username],
                          ),
                          const SizedBox(height: 10),
                          MyTextField(
                            controller: emailController,
                            focusNode: emailFocusNode,
                            hintText: "Email",
                            obscureText: false,
                            autofillHints: const [AutofillHints.email],
                          ),
                          const SizedBox(height: 10),
                          MyTextField(
                            controller: pwController,
                            focusNode: pwFocusNode,
                            hintText: "Password",
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                          ),
                          const SizedBox(height: 10),
                          MyTextField(
                            controller: confirmPwController,
                            focusNode: confirmPwFocusNode,
                            hintText: "Confirm Password",
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  MyButton(
                    text: "Register",
                    onTap: registerUser,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Already cool?"),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: widget.onTap,
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

void displayMessageToUser(String message, BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
