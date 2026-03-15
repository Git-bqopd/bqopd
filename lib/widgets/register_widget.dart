import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/button.dart';
import '../components/textfield.dart';

class RegisterWidget extends StatefulWidget {
  final void Function()? onTap;
  final VoidCallback? onRegisterSuccess; // NEW: Callback when registered

  const RegisterWidget({super.key, required this.onTap, this.onRegisterSuccess});

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

      if (widget.onRegisterSuccess != null) {
        widget.onRegisterSuccess!();
      }
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
    return AspectRatio(
      aspectRatio: 5 / 8,
      child: Container(
        color: const Color(0xFFF1B255),
        padding: const EdgeInsets.all(10.0), // Match FanzineWidget padding
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withOpacity(0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/logo200.gif', width: 150),
                      const SizedBox(height: 25),
                      const Text('bqopd', style: TextStyle(fontSize: 20)),
                      const SizedBox(height: 30),
                      Form(
                        child: AutofillGroup(
                          child: Column(
                            children: [
                              MyTextField(
                                controller: userNameController,
                                focusNode: userNameFocusNode,
                                hintText: "username",
                                obscureText: false,
                                autofillHints: const [AutofillHints.username],
                              ),
                              const SizedBox(height: 10),
                              MyTextField(
                                controller: emailController,
                                focusNode: emailFocusNode,
                                hintText: "email",
                                obscureText: false,
                                autofillHints: const [AutofillHints.email],
                              ),
                              const SizedBox(height: 10),
                              MyTextField(
                                controller: pwController,
                                focusNode: pwFocusNode,
                                hintText: "password",
                                obscureText: true,
                                autofillHints: const [AutofillHints.newPassword],
                              ),
                              const SizedBox(height: 10),
                              MyTextField(
                                controller: confirmPwController,
                                focusNode: confirmPwFocusNode,
                                hintText: "confirm password",
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      MyButton(
                        text: "register",
                        onTap: registerUser,
                        isLoading: _isLoading,
                      ),
                      const SizedBox(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("already cool?"),
                          const SizedBox(width: 5),
                          GestureDetector(
                            onTap: widget.onTap,
                            child: Text(
                              "login here",
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