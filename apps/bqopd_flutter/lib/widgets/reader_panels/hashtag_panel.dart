import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../hashtag_bar.dart';

class HashtagPanel extends StatelessWidget {
  final String imageId;

  const HashtagPanel({super.key, required this.imageId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('images').doc(imageId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final tags = data['tags'] as Map<String, dynamic>? ?? {};

        return SingleChildScrollView(
          child: HashtagBar(imageId: imageId, tags: tags),
        );
      },
    );
  }
}