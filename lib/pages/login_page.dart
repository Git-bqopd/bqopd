import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/fanzine_grid_view.dart';
import '../widgets/login_widget.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

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
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Center(
                child: LoginWidget(
                  onTap: () => context.go('/register'),
                ),
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>?;
            final shortCode = data?['login_zine_shortcode'] as String?;

            if (shortCode == null) {
              return Center(
                child: LoginWidget(
                  onTap: () => context.go('/register'),
                ),
              );
            }

            return FanzineGridView(
              shortCode: shortCode,
              uiWidget: Container(
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
                    onTap: () => context.go('/register'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

