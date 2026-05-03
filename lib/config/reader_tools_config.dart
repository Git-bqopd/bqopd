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
    bool isTwoPage = true, // Passed to determine if fanzine allows grid rendering
  }) {
    // 1. Role Gate
    final bool isElevated = userRole == 'admin' || userRole == 'moderator' || userRole == 'curator';
    if (tool.role == ToolRole.editor && !isElevated) return false;

    // 2. Editing Mode Gate
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
        if (!isTwoPage) return false; // Hidden if the fanzine is list-only
        if (!canOpenGrid) return false; // Hidden if already on desktop split or grid unavailable
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
    // --- CORE PUBLIC TOOLS (Locked Order & Always Visible) ---
    ReaderTool(
      id: 'Grid',
      label: 'open',
      description: 'Return to the grid navigation view.',
      defaultIcon: Icons.import_contacts,
      action: ToolAction.switchToGridView,
      condition: ToolCondition.hideOnDesktopSplit,
    ),
    ReaderTool(
      id: 'Like',
      label: 'like',
      description: 'Show appreciation for the work.',
      defaultIcon: Icons.favorite_border,
      activeIcon: Icons.favorite,
      action: ToolAction.toggleLike,
    ),

    // --- STANDARD PUBLIC TOOLS ---
    ReaderTool(
      id: 'Text',
      label: 'text',
      description: 'Read the finalized text.',
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
      id: 'Share',
      label: 'share',
      description: 'Copy a deep-link to this specific page.',
      defaultIcon: Icons.share_outlined,
      action: ToolAction.copyShareLink,
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
      id: 'Terminal',
      label: 'terminal',
      description: 'Access the interactive combat terminal.',
      defaultIcon: Icons.terminal_outlined,
      activeIcon: Icons.terminal,
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresGame,
      bonusRow: BonusRowType.terminal,
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
    ReaderTool(
      id: 'Entities',
      label: 'entities',
      description: 'View the people and subjects mentioned on this page.',
      defaultIcon: Icons.smart_toy_outlined, // Replaced Icon
      activeIcon: Icons.smart_toy, // Replaced Icon
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresOcrPipeline,
      bonusRow: BonusRowType.entities,
    ),

    // --- RESTRICTED EDITOR TOOLS ---
    ReaderTool(
      id: 'Raw',
      label: 'raw',
      description: 'View the raw OCR output.',
      defaultIcon: Icons.outdoor_grill,
      activeIcon: Icons.outdoor_grill,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.rawText,
    ),
    ReaderTool(
      id: 'Master',
      label: 'corrected',
      description: 'Edit the corrected master text.',
      defaultIcon: Icons.edit_document,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.masterText,
    ),
    ReaderTool(
      id: 'Linked',
      label: 'linked',
      description: 'Manually adjust wiki-links.',
      defaultIcon: Icons.add_link,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.linkedText,
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

    // --- SETTINGS TOOL (Absolute Last) ---
    ReaderTool(
      id: 'Settings',
      label: 'buttons',
      description: 'Customize which buttons appear on your toolbar.',
      defaultIcon: Icons.all_inclusive, // Changed to all_inclusive
      activeIcon: Icons.all_inclusive,  // Changed to all_inclusive
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.settings,
    ),
  ];
}