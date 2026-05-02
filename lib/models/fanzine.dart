import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum FanzineType { ingested, folio, calendar, article }

/// Canonical data model for the top-level Fanzine document.
class Fanzine extends Equatable {
  final String id;
  final String title;
  final String? volume;
  final String? issue;
  final String? wholeNumber;
  final FanzineType type;
  final bool isLive;
  final String processingStatus;

  /// The primary creator/uploader
  final String ownerId;

  /// A list of UIDs of users who have been granted permission to edit this work.
  final List<String> editors;

  final bool twoPage;
  final bool hasCover;
  final String? shortCode;
  final String? sourceFile;
  final List<String> draftEntities;
  final List<Map<String, dynamic>> masterCreators;
  final String? masterIndicia;

  final String? indiciaPageId;
  final int? startMonth;
  final int? startYear;
  final bool isSoftPublished;

  const Fanzine({
    required this.id,
    required this.title,
    this.volume,
    this.issue,
    this.wholeNumber,
    required this.type,
    required this.isLive,
    required this.processingStatus,
    required this.ownerId,
    this.editors = const [],
    this.twoPage = true, // Defaulting to true so the switch starts "ON"
    this.hasCover = true,
    this.shortCode,
    this.sourceFile,
    this.draftEntities = const [],
    this.masterCreators = const [],
    this.masterIndicia,
    this.indiciaPageId,
    this.startMonth,
    this.startYear,
    this.isSoftPublished = false,
  });

  factory Fanzine.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    FanzineType parsedType = FanzineType.ingested;
    if (data['type'] == 'folio') parsedType = FanzineType.folio;
    if (data['type'] == 'calendar') parsedType = FanzineType.calendar;
    if (data['type'] == 'article') parsedType = FanzineType.article;

    final String owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
    final List<String> editorList = List<String>.from(data['editors'] ?? []);

    return Fanzine(
      id: doc.id,
      title: data['title'] ?? 'Untitled',
      volume: data['volume'],
      issue: data['issue'],
      wholeNumber: data['wholeNumber'],
      type: parsedType,
      isLive: data['isLive'] ?? false,
      processingStatus: data['processingStatus'] ?? 'idle',
      ownerId: owner,
      editors: editorList,
      twoPage: data['twoPage'] ?? true, // Fallback to true if missing
      hasCover: data['hasCover'] ?? true,
      shortCode: data['shortCode'],
      sourceFile: data['sourceFile'],
      draftEntities: List<String>.from(data['draftEntities'] ?? []),
      masterCreators: (data['masterCreators'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      masterIndicia: data['masterIndicia'],
      indiciaPageId: data['indiciaPageId'],
      startMonth: data['startMonth'],
      startYear: data['startYear'],
      isSoftPublished: data['isSoftPublished'] ?? false,
    );
  }

  @override
  List<Object?> get props => [
    id, title, volume, issue, wholeNumber, type, isLive, processingStatus,
    ownerId, editors, twoPage, hasCover, shortCode, sourceFile,
    draftEntities, masterCreators, masterIndicia, indiciaPageId,
    startMonth, startYear, isSoftPublished
  ];
}