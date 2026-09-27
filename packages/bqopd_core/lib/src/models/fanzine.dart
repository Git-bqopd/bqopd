import 'package:equatable/equatable.dart';

enum FanzineType { ingested, folio, calendar }

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

  /// A list of UIDs of curators who cataloged or manage the metadata of this work.
  final List<String> curators;

  /// A list of UIDs of users or archives who own/contributed physical copies or scans of this work.
  final List<String> collections;

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
  final String? series;
  final String? publishedDate;
  final String? publishedDateMode; // 'day', 'month', 'year'
  final bool publishedDateGuess;

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
    this.curators = const [],
    this.collections = const [],
    this.twoPage = true,
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
    this.series,
    this.publishedDate,
    this.publishedDateMode = 'year',
    this.publishedDateGuess = false,
  });

  factory Fanzine.fromMap(String id, Map<String, dynamic> data) {
    FanzineType parsedType = FanzineType.ingested;
    if (data['type'] == 'folio') parsedType = FanzineType.folio;
    if (data['type'] == 'calendar') parsedType = FanzineType.calendar;
    final String owner =
        data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
    final List<String> editorList = List<String>.from(data['editors'] ?? []);
    final List<String> curatorList = List<String>.from(data['curators'] ?? []);
    final List<String> collectionList = List<String>.from(
      data['collections'] ?? data['collection'] ?? [],
    );

    return Fanzine(
      id: id,
      title: data['title'] ?? 'Untitled',
      volume: data['volume'],
      issue: data['issue'],
      wholeNumber: data['wholeNumber'],
      type: parsedType,
      isLive: data['isLive'] ?? false,
      processingStatus: data['processingStatus'] ?? 'idle',
      ownerId: owner,
      editors: editorList,
      curators: curatorList,
      collections: collectionList,
      twoPage: data['twoPage'] ?? true,
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
      series: data['series'],
      publishedDate: data['publishedDate'],
      publishedDateMode: data['publishedDateMode'] ?? 'year',
      publishedDateGuess: data['publishedDateGuess'] ?? false,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    volume,
    issue,
    wholeNumber,
    type,
    isLive,
    processingStatus,
    ownerId,
    editors,
    curators,
    collections,
    twoPage,
    hasCover,
    shortCode,
    sourceFile,
    draftEntities,
    masterCreators,
    masterIndicia,
    indiciaPageId,
    startMonth,
    startYear,
    isSoftPublished,
    series,
    publishedDate,
    publishedDateMode,
    publishedDateGuess,
  ];
}