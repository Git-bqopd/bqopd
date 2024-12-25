import 'package:flutter/material.dart';

class Responsive extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const Responsive ({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
});

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 904;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 1280 &&
      MediaQuery.sizeOf(context).width >= 904;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1280;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    // If our width is more than 1280 than we consider it a desktop.
    if (size.width >= 1280) {
      return desktop;
    }
    // If width is less than 1280 and more than 904 we consider it tablet.
    else if (size.width >= 904 && tablet != null) {
      return tablet!;
    }
    // Or less then that we call it mobile.
    else {
      return mobile;
    }
  }
}