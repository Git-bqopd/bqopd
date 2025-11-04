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

    final emailDocRef =
    FirebaseFirestore.instance.collection('Users').doc(currentUser.email);
    final uidDocRef =
    FirebaseFirestore.instance.collection('Users').doc(currentUser.uid);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        // 1) Try Users/{email}
        child: StreamBuilder<DocumentSnapshot>(
          stream: emailDocRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Users read error (email doc): ${snapshot.error}'),
              );
            }

            // If the email doc exists, use it.
            if (snapshot.hasData && snapshot.data!.exists) {
              return _buildFanzineFromUserDoc(snapshot.data!);
            }

            // 2) Fallback to Users/{uid}
            return StreamBuilder<DocumentSnapshot>(
              stream: uidDocRef.snapshots(),
              builder: (context, uidSnap) {
                if (uidSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (uidSnap.hasError) {
                  return Center(
                    child: Text('Users read error (uid doc): ${uidSnap.error}'),
                  );
                }
                if (!uidSnap.hasData || !uidSnap.data!.exists) {
                  return const Center(child: Text('User not found.'));
                }
                return _buildFanzineFromUserDoc(uidSnap.data!);
              },
            );
          },
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
