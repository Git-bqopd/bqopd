import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../hashtag_bar.dart';

/// Displays the hashtag management bar for a specific image.
/// This panel allows users to see, vote on, and add new tags.
class HashtagPanel extends StatelessWidget {
  final String imageId;

  const HashtagPanel({super.key, required this.imageId});

  @override
  Widget build(BuildContext context) {
    if (imageId.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          "Tagging unavailable for this page.",
          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('images').doc(imageId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("Error loading tags: ${snapshot.error}"),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final tags = data['tags'] as Map<String, dynamic>? ?? {};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "COMMUNITY TAGS",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            HashtagBar(imageId: imageId, tags: tags),
          ],
        );
      },
    );
  }
}