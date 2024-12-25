import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/button.dart';
import '../components/textfield.dart';
import '../helper/helper_functions.dart';

class RegisterPage extends StatefulWidget {
  final void Function()? onTap;
  const RegisterPage({super.key, required this.onTap});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // text controllers
  final TextEditingController userNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController pwController = TextEditingController();
  final TextEditingController confirmPwController = TextEditingController();

  // register user
  void registerUser() async {
    // show loading circle
    showDialog(
      context: context,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    // make sure passwords match
    if (pwController.text != confirmPwController.text) {
      // pop loading circle
      Navigator.pop(context);
      // show error to user
      displayMessageToUser("passwords don't match!", context);
    }

    // try creating the user
    try {
      // create the user
      UserCredential? userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text,
        password: pwController.text,
      );

      // create a user document and add to firestore
      createUserDocument(userCredential);

      // pop loading circle
      if (context.mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      // pop loading circle
      Navigator.pop(context);
      // display error message to user
      displayMessageToUser(e.code, context);
    }
  }

  // create a user document and collect them in firestore
  Future<void> createUserDocument(UserCredential? userCredential) async {
    if (userCredential != null && userCredential.user != null) {
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(userCredential.user!.email)
          .set({
        'email': userCredential.user!.email,
        'username': userNameController.text,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(11.0),
      child: Center(
        child: AspectRatio(
          aspectRatio: 5 / 8,
          child: Scaffold(
            backgroundColor: const Color(0xFFF1B255),
            body: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(25.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // logo
                      Image.asset(
                        'assets/logo200.gif', // Path to your GIF
                        width: 200, // Adjust width as needed
                      ),

                      const SizedBox(height: 25),

                      // slogan
                      const Text(
                        'bqopd',
                        style: TextStyle(
                          //fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),

                      const SizedBox(height: 50),

                      // userNameController textfield
                      MyTextField(
                        controller: userNameController,
                        hintText: "username",
                        obscureText: false,
                      ),

                      const SizedBox(height: 10),

                      // email textfield
                      MyTextField(
                        controller: emailController,
                        hintText: "email",
                        obscureText: false,
                      ),

                      const SizedBox(height: 10),

                      // password
                      MyTextField(
                        controller: pwController,
                        hintText: "password",
                        obscureText: true,
                      ),

                      const SizedBox(height: 10),

                      // confirm password
                      MyTextField(
                        controller: confirmPwController,
                        hintText: "confirm password",
                        obscureText: true,
                      ),

                      const SizedBox(height: 25),

                      // sign in button
                      MyButton(
                        text: "register",
                        onTap: registerUser,
                      ),

                      const SizedBox(height: 25),

                      // don't have an account? Register here
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "already cool?",
                          ),
                          const SizedBox(width: 5),
                          GestureDetector(
                            onTap: widget.onTap,
                            child: const Text(
                              "login here",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
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
