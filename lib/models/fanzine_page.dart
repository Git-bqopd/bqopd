import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Canonical data model for the Fanzine Page subcollection document.
class FanzinePage extends Equatable {
  final String id;
  final int pageNumber;
  final String? imageId;
  final String? imageUrl;
  final String? storagePath;
  final String status;
  final String? templateId;
  final DocumentReference reference;

  // Physical dimensions for assembly validation
  final int? width;
  final int? height;

  const FanzinePage({
    required this.id,
    required this.pageNumber,
    this.imageId,
    this.imageUrl,
    this.storagePath,
    required this.status,
    this.templateId,
    required this.reference,
    this.width,
    this.height,
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
      width: data['width'] as int?,
      height: data['height'] as int?,
    );
  }

  @override
  List<Object?> get props => [id, pageNumber, imageId, imageUrl, storagePath, status, templateId, width, height];
}