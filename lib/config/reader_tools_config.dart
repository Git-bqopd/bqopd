import 'package:flutter/material.dart';
import '../models/reader_tool.dart';

/// Central registry for all tools available in the Reader UI.
class ReaderToolsConfig {
  /// Centralized visibility logic used by both the toolbar and the settings matrix.
  static bool isToolVisibleInContext({
    required ReaderTool tool,
    required String userRole, // 'admin', 'moderator', 'curator', 'user'
    required bool isEditingMode,
    String? fanzineType, // 'folio', 'calendar', 'ingested'
    bool hasYoutube = false,
    bool isGame = false,
    bool isIndiciaPage = false,
    bool canOpenGrid = false,
  }) {
    // 1. Role Gate
    // Non-editors/admins/moderators can't see editor tools
    final bool isElevated = userRole == 'admin' || userRole == 'moderator' || userRole == 'curator';
    if (tool.role == ToolRole.editor && !isElevated) return false;

    // 2. Editing Mode Gate
    // Editor tools only show up if the UI is actually in editing mode
    if (tool.role == ToolRole.editor && !isEditingMode) return false;

    // 3. Conditionals
    switch (tool.condition) {
      case ToolCondition.requiresYouTube:
        if (!hasYoutube) return false;
        break;
      case ToolCondition.requiresGame:
        if (!isGame) return false;
        break;
      case ToolCondition.requiresIndicia:
        if (!isIndiciaPage) return false;
        break;
      case ToolCondition.hideOnDesktopSplit:
        if (!canOpenGrid) return false; // Usually only shows when looking at zine single-view
        break;
      case ToolCondition.requiresOcrPipeline:
        if (fanzineType == 'folio' || fanzineType == 'calendar') return false;
        break;
      case ToolCondition.always:
      default:
        break;
    }

    return true;
  }

  static const List<ReaderTool> tools = [
    // --- PUBLIC TOOLS ---
    ReaderTool(
      id: 'Text',
      label: 'text',
      description: 'View the transcribed text layer for easy reading.',
      defaultIcon: Icons.article_outlined,
      activeIcon: Icons.article,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.textReader,
    ),
    ReaderTool(
      id: 'Comment',
      label: 'comments',
      description: 'Join the discussion on this specific page.',
      defaultIcon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.comments,
    ),
    ReaderTool(
      id: 'Like',
      label: 'like',
      description: 'Show appreciation for the work.',
      defaultIcon: Icons.favorite_border,
      activeIcon: Icons.favorite,
      action: ToolAction.toggleLike,
    ),
    ReaderTool(
      id: 'Share',
      label: 'share',
      description: 'Copy a deep-link to this specific page.',
      defaultIcon: Icons.share_outlined,
      action: ToolAction.copyShareLink,
    ),
    ReaderTool(
      id: 'Grid',
      label: 'open',
      description: 'Return to the grid navigation view.',
      defaultIcon: Icons.grid_view,
      action: ToolAction.switchToGridView,
      condition: ToolCondition.hideOnDesktopSplit,
    ),
    ReaderTool(
      id: 'Settings',
      label: 'buttons',
      description: 'Customize which buttons appear on your toolbar.',
      defaultIcon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.settings,
    ),

    // --- CONDITIONAL PUBLIC TOOLS ---
    ReaderTool(
      id: 'YouTube',
      label: 'YouTube',
      description: 'Watch the video associated with this page.',
      defaultIcon: Icons.play_circle_outline,
      activeIcon: Icons.play_circle_filled,
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresYouTube,
      bonusRow: BonusRowType.youtube,
    ),
    ReaderTool(
      id: 'Tags',
      label: 'tags',
      description: 'Vote on hashtags and metadata.',
      defaultIcon: Icons.tag,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.tags,
    ),
    ReaderTool(
      id: 'Indicia',
      label: 'indicia',
      description: 'View publication information and copyright details.',
      defaultIcon: Icons.info_outline,
      activeIcon: Icons.info,
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresIndicia,
      bonusRow: BonusRowType.indicia,
    ),

    // --- RESTRICTED EDITOR TOOLS ---
    ReaderTool(
      id: 'Edit',
      label: 'edit',
      description: 'Edit page metadata and titles.',
      defaultIcon: Icons.edit_outlined,
      activeIcon: Icons.edit,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.editDetails,
    ),
    ReaderTool(
      id: 'OCR',
      label: 'ocr',
      description: 'Manage automated transcription status (Egg Mode).',
      defaultIcon: Icons.document_scanner_outlined,
      activeIcon: Icons.document_scanner,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresOcrPipeline,
      bonusRow: BonusRowType.ocr,
    ),
    ReaderTool(
      id: 'Entities',
      label: 'entities',
      description: 'Link detected names to internal profiles.',
      defaultIcon: Icons.link_outlined,
      activeIcon: Icons.link,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresOcrPipeline,
      bonusRow: BonusRowType.entities,
    ),
    ReaderTool(
      id: 'Publisher',
      label: 'publisher',
      description: 'Manage the layout and template (Chicken Mode).',
      defaultIcon: Icons.publish_outlined,
      activeIcon: Icons.publish,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.publisher,
    ),
    ReaderTool(
      id: 'Views',
      label: 'views',
      description: 'View detailed reader analytics for this content.',
      defaultIcon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.views,
    ),
    ReaderTool(
      id: 'Credits',
      label: 'credits',
      description: 'Manage archival metadata and contributor lists.',
      defaultIcon: Icons.manage_accounts_outlined,
      activeIcon: Icons.manage_accounts,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.credits,
    ),
  ];
}