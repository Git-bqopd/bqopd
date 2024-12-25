import 'package:bqopd/pages/game.dart';
import 'package:bqopd/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth/auth.dart';
import 'auth/login_or_register.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/sandbox.dart';
import 'pages/users_page.dart';
import 'theme/dark_mode.dart';
import 'theme/light_mode.dart';
import 'package:bqopd/services/storage/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(ChangeNotifierProvider(
      create: (context) => StorageService(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const AuthPage(),
          theme: lightMode,
          darkTheme: darkMode,
          routes: {
            '/login_register_page': (context) => const LoginOrRegister(),
            '/home_page': (context) => const HomePage(),
            '/profile_page': (context) => const ProfilePage(),
            '/game_page': (context) => const MooScreen(),
            '/user_page': (context) => const UserPage(),
            '/sandbox': (context) => const Sandbox(),
        },
      ),
    );
  }
}
