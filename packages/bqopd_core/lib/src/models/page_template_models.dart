import 'package:equatable/equatable.dart';
import 'fanzine.dart';

/// Defines an inline block element or component that can be placed inside a page layout
/// (e.g. an inline image, header, composite template block, or column break).
class PageBlockDefinition extends Equatable {
  final String id;
  final String name;
  final String description;
  final String syntaxExample;
  final List<String> requiredFields;
  final List<String> optionalFields;

  const PageBlockDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.syntaxExample,
    this.requiredFields = const [],
    this.optionalFields = const [],
  });

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    syntaxExample,
    requiredFields,
    optionalFields,
  ];
}

/// Defines a top-level page layout template (e.g., 3-column basic text, map cover, calendar spread).
class PageTemplateDefinition extends Equatable {
  final String id;
  final String name;
  final String description;
  final int width;
  final int height;
  final double aspectRatio;
  final Set<FanzineType> supportedFanzineTypes;
  final List<String> allowedBlockIds;
  final bool isMultiPageSource;
  final Map<String, dynamic> metadata;

  const PageTemplateDefinition({
    required this.id,
    required this.name,
    required this.description,
    this.width = 2000,
    this.height = 3200,
    this.aspectRatio = 0.625, // Standard 5:8 ratio
    this.supportedFanzineTypes = const {
      FanzineType.folio,
      FanzineType.ingested,
      FanzineType.calendar,
    },
    this.allowedBlockIds = const [],
    this.isMultiPageSource = false,
    this.metadata = const {},
  });

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    width,
    height,
    aspectRatio,
    supportedFanzineTypes,
    allowedBlockIds,
    isMultiPageSource,
    metadata,
  ];
}