import 'package:equatable/equatable.dart';

/// Canonical data model for the Fanzine Page subcollection document.
///
/// Represents an individual folio sheet, carrying asset storage paths,
/// display URLs, template parameters, and pre-rendered static HTML markup.
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
  final bool? is5x8;

  /// Raw markdown or transcription text content for search indexing or OCR editing.
  final String? text;

  /// Pre-rendered, frozen static HTML markup ready for instant zero-latency rendering.
  final String? textHtml;

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
    this.is5x8,
    this.text,
    this.textHtml,
  });

  factory FanzinePage.fromMap(String id, Map<String, dynamic> data) {
    return FanzinePage(
      id: id,
      pageNumber: data['pageNumber'] ?? 0,
      imageId: data['imageId'] as String?,
      imageUrl: data['imageUrl'] as String?,
      gridUrl: data['gridUrl'] as String?,
      listUrl: data['listUrl'] as String?,
      storagePath: data['storagePath'] as String?,
      status: (data['status'] ?? 'ready') as String,
      templateId: data['templateId'] as String?,
      spreadPosition: data['spreadPosition'] as String?,
      sidePreference: (data['sidePreference'] ?? 'either') as String,
      width: data['width'] as int?,
      height: data['height'] as int?,
      is5x8: data['is5x8'] as bool?,
      text: data['text'] as String?,
      textHtml: (data['text_html'] ?? data['textHtml']) as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pageNumber': pageNumber,
      if (imageId != null) 'imageId': imageId,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (gridUrl != null) 'gridUrl': gridUrl,
      if (listUrl != null) 'listUrl': listUrl,
      if (storagePath != null) 'storagePath': storagePath,
      'status': status,
      if (templateId != null) 'templateId': templateId,
      if (spreadPosition != null) 'spreadPosition': spreadPosition,
      'sidePreference': sidePreference,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (is5x8 != null) 'is5x8': is5x8,
      if (text != null) 'text': text,
      if (textHtml != null) 'text_html': textHtml,
    };
  }

  FanzinePage copyWith({
    String? id,
    int? pageNumber,
    String? imageId,
    String? imageUrl,
    String? gridUrl,
    String? listUrl,
    String? storagePath,
    String? status,
    String? templateId,
    String? spreadPosition,
    String? sidePreference,
    int? width,
    int? height,
    bool? is5x8,
    String? text,
    String? textHtml,
  }) {
    return FanzinePage(
      id: id ?? this.id,
      pageNumber: pageNumber ?? this.pageNumber,
      imageId: imageId ?? this.imageId,
      imageUrl: imageUrl ?? this.imageUrl,
      gridUrl: gridUrl ?? this.gridUrl,
      listUrl: listUrl ?? this.listUrl,
      storagePath: storagePath ?? this.storagePath,
      status: status ?? this.status,
      templateId: templateId ?? this.templateId,
      spreadPosition: spreadPosition ?? this.spreadPosition,
      sidePreference: sidePreference ?? this.sidePreference,
      width: width ?? this.width,
      height: height ?? this.height,
      is5x8: is5x8 ?? this.is5x8,
      text: text ?? this.text,
      textHtml: textHtml ?? this.textHtml,
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
    height,
    is5x8,
    text,
    textHtml,
  ];
}