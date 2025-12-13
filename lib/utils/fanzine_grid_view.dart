import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/fanzine_reader.dart'; // Import the new reader

class FanzineGridView extends StatelessWidget {
  final String shortCode;
  final Widget uiWidget;

  const FanzineGridView({
    super.key,
    required this.shortCode,
    required this.uiWidget,
  });

  @override
  Widget build(BuildContext context) {
    // If no shortcode provided, just render the UI Widget (The Cover/Login Widget)
    if (shortCode.isEmpty) {
      return FanzineReader(fanzineId: '', headerWidget: uiWidget);
    }

    // Step 1: try to find the fanzine by fanzines.where('shortCode' == shortCode)
    final fanzineByShortCodeStream = FirebaseFirestore.instance
        .collection('fanzines')
        .where('shortCode', isEqualTo: shortCode)
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: fanzineByShortCodeStream,
      builder: (context, fanzineSnapshot) {
        if (fanzineSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        String? fanzineId;

        if (fanzineSnapshot.hasData && fanzineSnapshot.data!.docs.isNotEmpty) {
          fanzineId = fanzineSnapshot.data!.docs.first.id;
        }

        // Step 2: fallback — try resolving via /shortcodes/<shortCode>
        if (fanzineId == null) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('shortcodes')
                .doc(shortCode)
                .snapshots(),
            builder: (context, scSnap) {
              if (scSnap.hasData && scSnap.data!.exists) {
                final data = scSnap.data!.data() as Map<String, dynamic>;
                final type = (data['type'] ?? '').toString();
                if (type == 'fanzine') {
                  fanzineId = (data['contentId'] ?? '').toString();
                }
              }

              // Use our new FanzineReader
              return FanzineReader(
                fanzineId: fanzineId ?? '',
                headerWidget: uiWidget,
              );
            },
          );
        }

        // If found in step 1
        return FanzineReader(
          fanzineId: fanzineId!,
          headerWidget: uiWidget,
        );
      },
    );
  }
}