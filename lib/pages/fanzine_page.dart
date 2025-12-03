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
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('User not logged in.')),
      );
    }

    // Define both references
    final uidDocRef =
    FirebaseFirestore.instance.collection('Users').doc(currentUser.uid);
    final emailDocRef =
    FirebaseFirestore.instance.collection('Users').doc(currentUser.email);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: false,
          // 1) CHECK UID FIRST (The New Standard)
          child: StreamBuilder<DocumentSnapshot>(
            stream: uidDocRef.snapshots(),
            builder: (context, uidSnapshot) {
              if (uidSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (uidSnapshot.hasError) {
                return Center(
                  child: Text('Users read error (uid doc): ${uidSnapshot.error}'),
                );
              }

              // If the UID doc exists, use it!
              if (uidSnapshot.hasData && uidSnapshot.data!.exists) {
                return _buildFanzineFromUserDoc(uidSnapshot.data!);
              }

              // 2) FALLBACK TO EMAIL (Legacy)
              // Only runs if the UID document was NOT found.
              return StreamBuilder<DocumentSnapshot>(
                stream: emailDocRef.snapshots(),
                builder: (context, emailSnapshot) {
                  if (emailSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (emailSnapshot.hasError) {
                    return Center(
                      child:
                      Text('Users read error (email doc): ${emailSnapshot.error}'),
                    );
                  }
                  if (!emailSnapshot.hasData || !emailSnapshot.data!.exists) {
                    return const Center(child: Text('User profile not found.'));
                  }
                  // If we found the old email doc, use that
                  return _buildFanzineFromUserDoc(emailSnapshot.data!);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFanzineFromUserDoc(DocumentSnapshot userDoc) {
    final data = (userDoc.data() ?? {}) as Map<String, dynamic>;
    final shortCodeRaw = data['newFanzine'];
    final shortCode = (shortCodeRaw is String && shortCodeRaw.trim().isNotEmpty)
        ? shortCodeRaw.trim()
        : null;

    if (shortCode == null) {
      return const Center(child: Text('No fanzine configured.'));
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
          child: const FanzineWidget(),
        ),
      ),
    );
  }
}