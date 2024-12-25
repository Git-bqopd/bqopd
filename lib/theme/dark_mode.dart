import 'package:flutter/material.dart';

ThemeData darkMode = ThemeData(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    surface: Color.fromARGB(255, 28, 28, 28),
    primary: Color.fromARGB(255, 33, 33, 33),
    secondary: Color.fromARGB(255, 79, 79, 79),
    inversePrimary: Colors.white,
  ),
);