enum ToolScope {
  reader,  // FanzineReaderPage SocialToolbar
  editor,  // FanzineEditor SocialToolbar (Maker)
  curator, // FanzineCurator SocialToolbar
}

enum ToolAction {
  openBonusRow,     // Opens the associated widget drawer
  toggleLike,       // Hits the engagement service to toggle like state
  copyShareLink,    // Copies the deep link to clipboard
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
  final BonusRowType? bonusRow;

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
    this.bonusRow,
  });
}