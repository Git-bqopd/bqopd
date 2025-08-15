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
            // While loading settings, show a progress indicator
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Shared login UI that can be shown with or without settings
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
                child: LoginWidget(
                  onTap: onTap,
                ),
              ),
            );

            // If settings are missing, fall back to basic login UI
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Center(child: loginUi);
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final shortCode = data['login_zine_shortcode'] as String?;

            // If the shortcode is missing, still allow user to log in
            if (shortCode == null) {
              return Center(child: loginUi);
            }

            // Settings were found; show the configured fanzine grid view
            return FanzineGridView(
              shortCode: shortCode,
              uiWidget: loginUi,
            );
          },
        ),
      ),
    );
  }
}

