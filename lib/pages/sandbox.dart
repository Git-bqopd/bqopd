import 'package:bqopd/pages/register_page.dart';
import 'package:flutter/material.dart';
import 'package:bqopd/pages/login_page.dart';
import '../responsive/responsive.dart';


class Sandbox extends StatelessWidget {
  const Sandbox({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: Responsive.isTablet(context) ? 1 : 1,
              child: LoginPage(onTap: () {},),
            ),
            if (!Responsive.isMobile(context))
            Expanded(
              child: RegisterPage(onTap: () {},),
            ),
          ],
        ),
      ),
    );
  }

}