import 'package:flutter/material.dart';

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
  requiresYouTube,    // Only shows if pageData has a youtubeId
  requiresGame,       // Only shows if pageData has isGame == true
  requiresIndicia,    // Only shows if pageId == fanzine.indiciaPageId
  requiresTwoPage,    // Only shows if the fanzine document has twoPage == true
  hideOnDesktopSplit, // Hidden if the desktop UI is already showing Grid and List side-by-side
  requiresOcrPipeline,// Hidden for manual 'folio' and 'calendar' types
}

/// Defines the specific widget drawer to mount when action == ToolAction.openBonusRow
enum BonusRowType {
  textReader,
  comments,
  editDetails,
  tags,
  ocr,
  entities,
  publisher,
  views,
  credits,
  youtube,
  indicia,
  settings,
}

/// The core data model for a dynamic toolbar button
class ReaderTool {
  final String id; // e.g., 'Comment', 'Share' (matches UserProvider visibility keys)
  final String label;
  final String description; // NEW: Brief description for the settings matrix
  final IconData defaultIcon;
  final IconData? activeIcon;
  final IconData? darkIcon;

  final ToolRole role;
  final ToolAction action;
  final ToolCondition condition;

  // Only required if action == ToolAction.openBonusRow
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
  }) : assert(
  action != ToolAction.openBonusRow || bonusRow != null,
  'bonusRow must be provided if action is openBonusRow',
  );
}