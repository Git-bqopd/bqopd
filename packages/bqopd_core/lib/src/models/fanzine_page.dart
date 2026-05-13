import 'package:equatable/equatable.dart';

/// Canonical data model for the Fanzine Page subcollection document.
class FanzinePage extends Equatable {
  final String id;
  final int pageNumber;
  final String? imageId;
  final String? imageUrl;
  final String? gridUrl;
  final String? listUrl;
  final String? storagePath;
  final String status;
  final String? templateId;

  final String? spreadPosition;
  final String sidePreference;

  final int? width;
  final int? height;

  const FanzinePage({
    required this.id,
    required this.pageNumber,
    this.imageId,
    this.imageUrl,
    this.gridUrl,
    this.listUrl,
    this.storagePath,
    required this.status,
    this.templateId,
    this.spreadPosition,
    this.sidePreference = 'either',
    this.width,
    this.height,
  });

  factory FanzinePage.fromMap(String id, Map<String, dynamic> data) {
    return FanzinePage(
      id: id,
      pageNumber: data['pageNumber'] ?? 0,
      imageId: data['imageId'],
      imageUrl: data['imageUrl'],
      gridUrl: data['gridUrl'],
      listUrl: data['listUrl'],
      storagePath: data['storagePath'],
      status: data['status'] ?? 'ready',
      templateId: data['templateId'],
      spreadPosition: data['spreadPosition'],
      sidePreference: data['sidePreference'] ?? 'either',
      width: data['width'] as int?,
      height: data['height'] as int?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    pageNumber,
    imageId,
    imageUrl,
    gridUrl,
    listUrl,
    storagePath,
    status,
    templateId,
    spreadPosition,
    sidePreference,
    width,
    height
  ];
}