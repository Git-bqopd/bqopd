import 'package:bqopd/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'auth/auth.dart';
import 'auth/login_or_register.dart';
import 'pages/fanzine_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const AuthPage(),
        routes: {
          '/login_register_page': (context) => const LoginOrRegister(),
          '/fanzine_page': (context) => const FanzinePage(),
        },
      ),
    );
  }
}
