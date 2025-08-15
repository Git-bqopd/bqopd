import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/fanzine_grid_view.dart';
import '../widgets/login_widget.dart';

class LoginPage extends StatelessWidget {
  final void Function()? onTap;

  const LoginPage({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('app_settings')
              .doc('main_settings')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Base login widget used when remote settings are missing
            final loginUi = Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: LoginWidget(onTap: onTap),
              ),
            );

            if (!snapshot.hasData || !snapshot.data!.exists) {
              // If settings aren't available yet, still show the login form
              return Center(child: loginUi);
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final shortCode = data['login_zine_shortcode'] as String?;
            if (shortCode == null) {
              // Fallback to plain login when no shortcode is configured
              return Center(child: loginUi);
            }

            return FanzineGridView(shortCode: shortCode, uiWidget: loginUi);
          },
        ),
      ),
    );
  }
}

