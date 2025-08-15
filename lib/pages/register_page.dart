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
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Center(child: RegisterWidget(onTap: onTap));
            }
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final shortCode = data['register_zine_shortcode'] as String?;
            if (shortCode == null) {
              return Center(child: RegisterWidget(onTap: onTap));
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
                  child: RegisterWidget(
                    onTap: onTap,
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

