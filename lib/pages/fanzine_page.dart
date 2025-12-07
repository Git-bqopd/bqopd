import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/fanzine_grid_view.dart';
import '../widgets/fanzine_widget.dart';

class FanzinePage extends StatelessWidget {
  const FanzinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final db = FirebaseFirestore.instance;

    // --- 1. Determine Data Source ---
    Stream<DocumentSnapshot> shortcodeSourceStream;

    if (currentUser != null) {
      // LOGGED IN: Get the user's personal Fanzine shortcode from their User doc
      shortcodeSourceStream = db.collection('Users').doc(currentUser.uid).snapshots();
    } else {
      // NOT LOGGED IN (PUBLIC): Get the "Login Zine" shortcode from app_settings
      shortcodeSourceStream = db.collection('app_settings').doc('main_settings').snapshots();
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: false,
          child: StreamBuilder<DocumentSnapshot>(
            stream: shortcodeSourceStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: Text('Fanzine configuration not found.'));
              }

              final data = snapshot.data!.data() as Map<String, dynamic>;
              String? shortCode;

              if (currentUser != null) {
                // Logged In: Use 'newFanzine' from the User document
                shortCode = data['newFanzine'] as String?;
              } else {
                // Not Logged In: Use 'login_zine_shortcode' from app_settings
                shortCode = data['login_zine_shortcode'] as String?;
              }

              if (shortCode == null || shortCode.isEmpty) {
                return Center(
                  child: Text(
                    currentUser != null
                        ? 'Welcome! You have no featured fanzine yet.'
                        : 'Default public fanzine not configured.',
                  ),
                );
              }

              // Determine which mode FanzineWidget should operate in
              final isDashboardMode = currentUser != null;

              return FanzineGridView(
                shortCode: shortCode,
                // uiWidget will display the Fanzine Widget configured for either:
                // 1. DASHBOARD Mode (fanzineShortCode: null) -> fetches user's username/link
                // 2. PUBLIC Mode (fanzineShortCode: shortCode) -> fetches creator's link or "Login/Register"
                uiWidget: FanzineWidget(
                  fanzineShortCode: isDashboardMode ? null : shortCode,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}