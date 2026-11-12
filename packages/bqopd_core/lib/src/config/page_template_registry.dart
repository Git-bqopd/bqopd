import '../models/fanzine.dart';
import '../models/page_template_models.dart';

/// Centralized registry cataloging all top-level page templates and inline block elements.
/// Serves as the single source of truth for both Web (Jaspr) and Flutter layout generation.
class PageTemplateRegistry {
  // ---------------------------------------------------------------------------
  // 1. Block Elements Catalog (elements that can be placed inside page templates)
  // ---------------------------------------------------------------------------
  static const Map<String, PageBlockDefinition> blocks = {
    // Basic Paragraph Text
    'text': PageBlockDefinition(
      id: 'text',
      name: 'Paragraph Text',
      description: 'Standard justified body text flowing through columns.',
      syntaxExample: 'Plain markdown paragraph text.',
      requiredFields: ['content'],
    ),

    // Header Level 1 (Impact / Banner Title)
    'h1': PageBlockDefinition(
      id: 'h1',
      name: 'Heading 1',
      description: 'Top-level 42px Impact bold heading.',
      syntaxExample: '# ARTICLE TITLE',
      requiredFields: ['content'],
    ),

    // Header Level 2 (Section Subtitle)
    'h2': PageBlockDefinition(
      id: 'h2',
      name: 'Heading 2',
      description: 'Section-level 36px Impact bold heading.',
      syntaxExample: '## Section Subheading',
      requiredFields: ['content'],
    ),

    // Header Level 3 (Sub-section Title)
    'h3': PageBlockDefinition(
      id: 'h3',
      name: 'Heading 3',
      description: 'Minor 28px Impact bold heading.',
      syntaxExample: '### Category Subheading',
      requiredFields: ['content'],
    ),

    // Bullet List Item
    'bullet': PageBlockDefinition(
      id: 'bullet',
      name: 'Bullet Point',
      description: 'Indented list item marked with an asterisk or hyphen.',
      syntaxExample: '* Contributor Name',
      requiredFields: ['content'],
    ),

    // Column Break Control
    'column_break': PageBlockDefinition(
      id: 'column_break',
      name: 'Column Break',
      description: 'Forces subsequent layout content to jump directly to the next column.',
      syntaxExample: '{{COLUMN_BREAK}} or [[COLUMN_BREAK]]',
    ),

    // Single Inline Image with dynamic aspect ratio preservation
    'image': PageBlockDefinition(
      id: 'image',
      name: 'Column Image Asset',
      description: 'Full-width column image scaled to match its natural aspect ratio.',
      syntaxExample: '{{IMAGE: https://example.com/scan.jpg | ratio=0.625}} or {{IMAGE: url | 608x972}}',
      requiredFields: ['url'],
      optionalFields: ['width', 'height', 'aspectRatio', 'ratio'],
    ),

    // Composite Block: Template 1 (Image + Caption)
    'template_1': PageBlockDefinition(
      id: 'template_1',
      name: 'Composite Image & Caption',
      description: 'Embedded image scaled to natural aspect ratio with auto-wrapping caption text and optional row offset.',
      syntaxExample: '{{TEMPLATE_1: url | row=5 | 608x972 | Caption text}} or {{1|img01|Caption}}',
      requiredFields: ['url', 'caption'],
      optionalFields: ['row', 'width', 'height', 'aspectRatio', 'ratio'],
    ),

    // Terminal QR / WebAR Anchor Stamp
    'terminal_qr_anchor': PageBlockDefinition(
      id: 'terminal_qr_anchor',
      name: 'Terminal QR & WebAR Fiducial Stamp',
      description: 'Scannable shortcode QR + high-contrast fiducial frame for evergreen Digital Twin lookup and Smartphone WebAR tracking.',
      syntaxExample: '{{TERMINAL_QR: shortCode=7GWH01 | mode=anchor}}',
      requiredFields: ['shortCode'],
      optionalFields: ['mode', 'roomId'],
    ),

    // Terminal Stat / Contraband Table
    'terminal_stat_table': PageBlockDefinition(
      id: 'terminal_stat_table',
      name: 'Terminal Stat & Contraband Ledger',
      description: 'Monospace TTRPG stat block, weapon chart, or black-market price list.',
      syntaxExample: '{{TERMINAL_STATS: entityId=thug_7g_01}}',
      requiredFields: ['entityId'],
      optionalFields: ['showInventory', 'showPrices'],
    ),
  };

  // ---------------------------------------------------------------------------
  // 2. Top-Level Page Templates Catalog
  // ---------------------------------------------------------------------------
  static const Map<String, PageTemplateDefinition> templates = {
    // 3-Column Publisher Page (Standard Body Layout)
    'basic_text': PageTemplateDefinition(
      id: 'basic_text',
      name: '3-Column Publisher Page',
      description: 'A 2000x3200 3-column canvas designed for continuous markdown and letters flow.',
      width: 2000,
      height: 3200,
      aspectRatio: 0.625,
      isMultiPageSource: true,
      supportedFanzineTypes: {
        FanzineType.folio,
        FanzineType.ingested,
      },
      allowedBlockIds: [
        'text',
        'h1',
        'h2',
        'h3',
        'bullet',
        'column_break',
        'image',
        'template_1',
      ],
      metadata: {
        'columnCount': 3,
        'columnWidth': 608,
        'columnXOffsets': [33, 696, 1359],
        'usableColumnHeight': 3087,
      },
    ),

    // Geospatial Illustrated Map Cover Page
    'map_cover': PageTemplateDefinition(
      id: 'map_cover',
      name: 'Geospatial Map Cover',
      description: 'A 2000x3200 illustrated Google Map cover with center pin, radial markers, and UI chrome.',
      width: 2000,
      height: 3200,
      aspectRatio: 0.625,
      isMultiPageSource: false,
      supportedFanzineTypes: {
        FanzineType.folio,
      },
      allowedBlockIds: [],
      metadata: {
        'requiresCloudFunction': 'fetch_static_map',
        'supportsCenterPin': true,
        'supportsLetterPins': true,
      },
    ),

    // Convention Calendar - Left Page (First 6 months)
    'calendar_left': PageTemplateDefinition(
      id: 'calendar_left',
      name: 'Calendar Spread (Left / Months 1-6)',
      description: 'A 2000x3200 6-month convention date grid for Thursday-Sunday events.',
      width: 2000,
      height: 3200,
      aspectRatio: 0.625,
      isMultiPageSource: false,
      supportedFanzineTypes: {
        FanzineType.calendar,
      },
      allowedBlockIds: [],
      metadata: {
        'monthsCount': 6,
        'spreadSide': 'left',
      },
    ),

    // Convention Calendar - Right Page (Last 6 months)
    'calendar_right': PageTemplateDefinition(
      id: 'calendar_right',
      name: 'Calendar Spread (Right / Months 7-12)',
      description: 'A 2000x3200 6-month convention date grid concluding the 12-month calendar.',
      width: 2000,
      height: 3200,
      aspectRatio: 0.625,
      isMultiPageSource: false,
      supportedFanzineTypes: {
        FanzineType.calendar,
      },
      allowedBlockIds: [],
      metadata: {
        'monthsCount': 6,
        'spreadSide': 'right',
      },
    ),

    // -------------------------------------------------------------------------
    // `terminal` Cyberpunk TTRPG & WebAR Page Templates (2000x3200 / 5:8)
    // -------------------------------------------------------------------------

    // 1. Overhead Tactical Grid Map (1 Positional WebAR Anchor)
    'terminal_grid_map': PageTemplateDefinition(
      id: 'terminal_grid_map',
      name: 'Terminal Overhead Tactical Grid Map',
      description: 'A 2000x3200 top-down Kenney 2D blueprint grid of an Apartment, HQ, or Rented Warehouse with a positional WebAR fiducial anchor.',
      width: 2000,
      height: 3200,
      aspectRatio: 0.625,
      isMultiPageSource: false,
      supportedFanzineTypes: {
        FanzineType.folio,
      },
      allowedBlockIds: [
        'h1',
        'h2',
        'text',
        'terminal_qr_anchor',
        'terminal_stat_table',
      ],
      metadata: {
        'isTerminalPage': true,
        'supportsPositionalWebAr': true,
        'preferredSide': 'left',
        'defaultGridColumns': 8,
        'defaultGridRows': 10,
      },
    ),

    // 2. Character / Crew Dossier & Turn Order Sheet (Scan-Once +5 QR Participant)
    'terminal_dossier': PageTemplateDefinition(
      id: 'terminal_dossier',
      name: 'Terminal Persona Dossier & Weekly Orders',
      description: 'A 2000x3200 facing character/turf ledger showing stats, gear, weekly incident logs, and scannable QR participant badge.',
      width: 2000,
      height: 3200,
      aspectRatio: 0.625,
      isMultiPageSource: false,
      supportedFanzineTypes: {
        FanzineType.folio,
      },
      allowedBlockIds: [
        'h1',
        'h2',
        'h3',
        'text',
        'bullet',
        'terminal_qr_anchor',
        'terminal_stat_table',
      ],
      metadata: {
        'isTerminalPage': true,
        'supportsScanOnceIngest': true,
        'preferredSide': 'right',
      },
    ),

    // 3. Cyberpunk Screamsheet (Canonical World News & Bounties)
    'terminal_screamsheet': PageTemplateDefinition(
      id: 'terminal_screamsheet',
      name: 'Terminal Street Screamsheet',
      description: 'A 2000x3200 sensationalist street newspaper auto-typeset from canonical WorldEvent history, turf wars, and active bounties.',
      width: 2000,
      height: 3200,
      aspectRatio: 0.625,
      isMultiPageSource: false,
      supportedFanzineTypes: {
        FanzineType.folio,
      },
      allowedBlockIds: [
        'h1',
        'h2',
        'h3',
        'text',
        'bullet',
        'column_break',
        'terminal_qr_anchor',
      ],
      metadata: {
        'isTerminalPage': true,
        'columnCount': 3,
      },
    ),

    // 4. 1-Page Drama Advertisement (Contextual Encounter Mini-Game)
    'terminal_drama_ad': PageTemplateDefinition(
      id: 'terminal_drama_ad',
      name: 'Terminal 1-Page Encounter Advertisement',
      description: 'A 2000x3200 1-page contraband/gang ad engineered to spark reader-driven drama via the terminal social button and QR scan.',
      width: 2000,
      height: 3200,
      aspectRatio: 0.625,
      isMultiPageSource: false,
      supportedFanzineTypes: {
        FanzineType.folio,
      },
      allowedBlockIds: [
        'h1',
        'h2',
        'text',
        'image',
        'terminal_qr_anchor',
        'terminal_stat_table',
      ],
      metadata: {
        'isTerminalPage': true,
        'supportsScanOnceIngest': true,
        'isBackfillEligible': true,
      },
    ),
  };

  // ---------------------------------------------------------------------------
  // Lookup and Query Helpers
  // ---------------------------------------------------------------------------
  /// Retrieves a page template definition by its unique [id].
  static PageTemplateDefinition? getTemplate(String? id) {
    if (id == null) return null;
    return templates[id];
  }

  /// Retrieves a block definition by its unique [id].
  static PageBlockDefinition? getBlock(String? id) {
    if (id == null) return null;
    return blocks[id];
  }

  /// Returns all registered page templates.
  static List<PageTemplateDefinition> getAllTemplates() {
    return templates.values.toList();
  }

  /// Returns all registered `terminal` TTRPG page templates.
  static List<PageTemplateDefinition> getTerminalTemplates() {
    return templates.values
        .where((tmpl) => tmpl.metadata['isTerminalPage'] == true)
        .toList();
  }

  /// Returns all registered block elements.
  static List<PageBlockDefinition> getAllBlocks() {
    return blocks.values.toList();
  }

  /// Returns all page templates supported by a given [FanzineType].
  static List<PageTemplateDefinition> getTemplatesForFanzineType(FanzineType type) {
    return templates.values
        .where((tmpl) => tmpl.supportedFanzineTypes.contains(type))
        .toList();
  }

  /// Returns the allowed [PageBlockDefinition]s for a given [templateId].
  static List<PageBlockDefinition> getAllowedBlocksForTemplate(String templateId) {
    final template = getTemplate(templateId);
    if (template == null) return const [];
    return template.allowedBlockIds
        .map((blockId) => blocks[blockId])
        .whereType<PageBlockDefinition>()
        .toList();
  }
}
