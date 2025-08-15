import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/register_widget.dart';
import '../utils/fanzine_grid_view.dart';

class RegisterPage extends StatelessWidget {
  final void Function()? onTap;

  const RegisterPage({super.key, required this.onTap});

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
            // While loading settings, show progress
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Shared register UI used as fallback when settings missing
            final registerUi = Container(
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
                child: RegisterWidget(
                  onTap: onTap,
                ),
              ),
            );

            // If settings are missing, allow registration without zine
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Center(child: registerUi);
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final shortCode = data['register_zine_shortcode'] as String?;

            // If no shortcode configured, show standalone register widget
            if (shortCode == null) {
              return Center(child: registerUi);
            }

            // Settings found; display fanzine grid view with register widget
            return FanzineGridView(
              shortCode: shortCode,
              uiWidget: registerUi,
            );
          },
        ),
      ),
    );
  }
}

