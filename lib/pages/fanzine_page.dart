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
              // Note: We don't block on 'waiting' here to prevent white flash if possible,
              // but standard practice is a loader.
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              String? shortCode;

              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data != null) {
                  if (currentUser != null) {
                    // Logged In: Use 'newFanzine' (fallback to nothing if not set)
                    shortCode = data['newFanzine'] as String?;
                  } else {
                    // Not Logged In: Use 'login_zine_shortcode'
                    shortCode = data['login_zine_shortcode'] as String?;
                  }
                }
              }

              // Determine which mode FanzineWidget should operate in
              final isDashboardMode = currentUser != null;

              // IF NO SHORTCODE IS FOUND (e.g. database not set up, or new user):
              // We pass an empty string or null. The FanzineGridView handles this
              // by just showing the uiWidget (the FanzineWidget) and no image tiles.
              return FanzineGridView(
                shortCode: shortCode ?? '',
                uiWidget: FanzineWidget(
                  // If dashboard mode, we pass null so FanzineWidget loads "My Dashboard" logic
                  // If public mode, we pass the shortCode so it loads that specific zine (or nothing)
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