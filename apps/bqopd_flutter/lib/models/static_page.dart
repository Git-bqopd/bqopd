import 'package:cloud_firestore/cloud_firestore.dart';

class StaticPage {
  final String id;
  final String imageUrl;
  final double aspectRatio;
  final DateTime createdAt;

  StaticPage({
    required this.id,
    required this.imageUrl,
    this.aspectRatio = 0.625, // Default 5:8
    required this.createdAt,
  });

  factory StaticPage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StaticPage(
      id: doc.id,
      imageUrl: data['imageUrl'] ?? '',
      aspectRatio: (data['aspectRatio'] as num?)?.toDouble() ?? 0.625,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'imageUrl': imageUrl,
      'aspectRatio': aspectRatio,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
