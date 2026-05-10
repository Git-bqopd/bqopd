/// Defines who is allowed to see the button
enum ToolRole {
  public, // Visible to everyone
  editor, // Visible only to curators/editors
}

/// Defines what happens when the button is clicked
enum ToolAction {
  openBonusRow,     // Opens the associated widget drawer
  toggleLike,       // Hits the engagement service to toggle like state
  copyShareLink,    // Copies the deep link to clipboard
  switchToGridView, // Triggers layout change back to the Grid/Navigation view
}

/// Defines conditional visibility based on the specific page's data or layout state
enum ToolCondition {
  always,
  requiresYouTube,
  requiresGame,
  requiresIndicia,
  requiresTwoPage,
  hideOnDesktopSplit,
  requiresOcrPipeline,
}

/// Defines the specific widget drawer to mount
enum BonusRowType {
  textReader,
  rawText,
  masterText,
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

  final ToolRole role;
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
    this.role = ToolRole.public,
    this.action = ToolAction.openBonusRow,
    this.condition = ToolCondition.always,
    this.bonusRow,
  });
}