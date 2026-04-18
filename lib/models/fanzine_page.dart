import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical data model for the Fanzine Page subcollection document.
class FanzinePage {
  final String id;
  final int pageNumber;
  final String? imageId;
  final String? imageUrl;
  final String? storagePath;
  final String status;
  final String? templateId;
  final DocumentReference reference;

  FanzinePage({
    required this.id,
    required this.pageNumber,
    this.imageId,
    this.imageUrl,
    this.storagePath,
    required this.status,
    this.templateId,
    required this.reference,
  });

  /// Safely parses Firestore maps, providing fallbacks.
  factory FanzinePage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FanzinePage(
      id: doc.id,
      pageNumber: data['pageNumber'] ?? 0,
      imageId: data['imageId'],
      imageUrl: data['imageUrl'],
      storagePath: data['storagePath'],
      status: data['status'] ?? 'ready',
      templateId: data['templateId'],
      reference: doc.reference,
    );
  }
}