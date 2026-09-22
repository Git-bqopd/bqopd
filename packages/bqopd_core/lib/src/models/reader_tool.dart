enum ToolScope {
  reader,  // FanzineReaderPage SocialToolbar
  editor,  // FanzineEditor SocialToolbar (Maker)
  curator, // FanzineCurator SocialToolbar
}

/// Extension providing centralized, type-safe route slug mapping for tool scopes
/// across both Jaspr Web and Flutter platforms.
extension ToolScopeRouting on ToolScope {
  /// Maps enum to the public URL path slug
  String toRouteSlug() {
    switch (this) {
      case ToolScope.reader:
        return 'reader';
      case ToolScope.editor:
        return 'maker';
      case ToolScope.curator:
        return 'curator';
    }
  }

  /// Resolves route path strings safely to their enum representation
  static ToolScope fromRouteSlug(String? slug, {ToolScope fallback = ToolScope.reader}) {
    if (slug == null) return fallback;
    switch (slug.toLowerCase().trim()) {
      case 'curator':
        return ToolScope.curator;
      case 'maker':
      case 'editor':
        return ToolScope.editor;
      case 'reader':
      default:
        return ToolScope.reader;
    }
  }
}

enum ToolAction {
  openBonusRow,     // Opens the associated widget drawer or panel
  toggleLike,       // Hits the engagement service to toggle like state
  copyShareLink,    // Copies the canonical deep link to clipboard
  switchToGridView, // Triggers layout change back to the Grid/Navigation view
}

enum ToolCondition {
  always,
  requiresYouTube,
  requiresGame,
  requiresIndicia,
  requiresTwoPage,
  hideOnDesktopSplit,
  requiresOcrPipeline,
}

enum BonusRowType {
  textReader,
  rawText,
  editText,
  linkedText,
  comments,
  editDetails,
  tags,
  entities,
  views,
  credits,
  youtube,
  indicia,
  settings,
  analyticsDashboard,
  shareOptions,
  terminal,
  newPage,
}

/// Pure Dart data model for a dynamic toolbar button.
/// Icons are stored as Strings to avoid Flutter dependencies.
/// Supports dedicated bonus row (mobile accordion drawer) and bonus column
/// (desktop 3rd column window) panel targets per workspace scope.
class ReaderTool {
  final String id;
  final String label;
  final String description;
  final String defaultIcon; // String ID: e.g. "article_outlined"
  final String? activeIcon;
  final String? darkIcon;
  final Set<ToolScope> scopes;
  final ToolAction action;
  final ToolCondition condition;

  /// General fallback bonus row (used if scope-specific bonus rows are omitted).
  final BonusRowType? _bonusRow;

  /// Scope-specific panel destinations for mobile / inline bonus row:
  final BonusRowType? readerBonusRow;
  final BonusRowType? editorBonusRow;
  final BonusRowType? curatorBonusRow;

  /// General fallback bonus column (used if scope-specific bonus columns are omitted).
  final BonusRowType? _bonusColumn;

  /// Scope-specific panel destinations for desktop 3rd column:
  final BonusRowType? readerBonusColumn;
  final BonusRowType? editorBonusColumn;
  final BonusRowType? curatorBonusColumn;

  const ReaderTool({
    required this.id,
    required this.label,
    required this.description,
    required this.defaultIcon,
    this.activeIcon,
    this.darkIcon,
    this.scopes = const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
    this.action = ToolAction.openBonusRow,
    this.condition = ToolCondition.always,
    BonusRowType? bonusRow,
    this.readerBonusRow,
    this.editorBonusRow,
    this.curatorBonusRow,
    BonusRowType? bonusColumn,
    this.readerBonusColumn,
    this.editorBonusColumn,
    this.curatorBonusColumn,
  })  : _bonusRow = bonusRow,
        _bonusColumn = bonusColumn;

  /// Backward-compatible getter resolving either the general or scope-specific panel.
  BonusRowType? get bonusRow =>
      _bonusRow ?? readerBonusRow ?? editorBonusRow ?? curatorBonusRow;

  /// Backward-compatible getter resolving either the general or scope-specific bonus column,
  /// falling back to [bonusRow] if no column-specific configuration exists.
  BonusRowType? get bonusColumn =>
      _bonusColumn ??
          readerBonusColumn ??
          editorBonusColumn ??
          curatorBonusColumn ??
          bonusRow;

  /// Returns the specific panel configured for the given [ToolScope] in mobile / inline bonus row mode.
  BonusRowType? getBonusRowForScope(ToolScope scope) {
    switch (scope) {
      case ToolScope.reader:
        return readerBonusRow ?? _bonusRow;
      case ToolScope.editor:
        return editorBonusRow ?? _bonusRow;
      case ToolScope.curator:
        return curatorBonusRow ?? _bonusRow;
    }
  }

  /// Returns the specific panel configured for the given [ToolScope] in desktop 3rd column mode,
  /// falling back to [getBonusRowForScope] if no column-specific panel is provided.
  BonusRowType? getBonusColumnForScope(ToolScope scope) {
    final specificColumn = switch (scope) {
      ToolScope.reader => readerBonusColumn,
      ToolScope.editor => editorBonusColumn,
      ToolScope.curator => curatorBonusColumn,
    };
    return specificColumn ?? _bonusColumn ?? getBonusRowForScope(scope);
  }
}