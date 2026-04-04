import 'package:flutter/material.dart';
import '../models/reader_tool.dart';

/// Central registry for all tools available in the Reader UI.
class ReaderToolsConfig {
  static const List<ReaderTool> tools = [
    // --- PUBLIC TOOLS ---
    ReaderTool(
      id: 'Text',
      label: 'Read Text',
      defaultIcon: Icons.article_outlined,
      activeIcon: Icons.article,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.textReader,
    ),
    ReaderTool(
      id: 'Comment',
      label: 'Comments',
      defaultIcon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.comments,
    ),
    ReaderTool(
      id: 'Like',
      label: 'Like Page',
      defaultIcon: Icons.favorite_border,
      activeIcon: Icons.favorite,
      action: ToolAction.toggleLike,
    ),
    ReaderTool(
      id: 'Share',
      label: 'Share Link',
      defaultIcon: Icons.share_outlined,
      action: ToolAction.copyShareLink,
    ),
    ReaderTool(
      id: 'Grid',
      label: 'View Pages',
      defaultIcon: Icons.grid_view,
      action: ToolAction.switchToGridView,
      condition: ToolCondition.hideOnDesktopSplit,
    ),
    ReaderTool(
      id: 'Settings',
      label: 'Customize Buttons',
      defaultIcon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.settings,
    ),

    // --- CONDITIONAL PUBLIC TOOLS ---
    ReaderTool(
      id: 'YouTube',
      label: 'Watch Video',
      defaultIcon: Icons.play_circle_outline,
      activeIcon: Icons.play_circle_filled,
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresYouTube,
      bonusRow: BonusRowType.youtube,
    ),
    ReaderTool(
      id: 'Tags',
      label: 'Hashtags',
      defaultIcon: Icons.tag,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.tags,
    ),
    ReaderTool(
      id: 'Indicia',
      label: 'Issue Indicia',
      defaultIcon: Icons.info_outline,
      activeIcon: Icons.info,
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresIndicia,
      bonusRow: BonusRowType.indicia,
    ),

    // --- RESTRICTED EDITOR TOOLS ---
    ReaderTool(
      id: 'Edit',
      label: 'Edit Page Info',
      defaultIcon: Icons.edit_outlined,
      activeIcon: Icons.edit,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.editDetails,
    ),
    ReaderTool(
      id: 'OCR',
      label: 'OCR Pipeline',
      defaultIcon: Icons.document_scanner_outlined,
      activeIcon: Icons.document_scanner,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.ocr,
    ),
    ReaderTool(
      id: 'Entities',
      label: 'Page Entities',
      defaultIcon: Icons.link_outlined,
      activeIcon: Icons.link,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.entities,
    ),
    ReaderTool(
      id: 'Publisher',
      label: 'Publisher Editor',
      defaultIcon: Icons.publish_outlined,
      activeIcon: Icons.publish,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.publisher,
    ),
    ReaderTool(
      id: 'Views',
      label: 'Analytics',
      defaultIcon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.views,
    ),
    ReaderTool(
      id: 'Credits',
      label: 'Archival Metadata',
      defaultIcon: Icons.manage_accounts_outlined,
      activeIcon: Icons.manage_accounts,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.credits,
    ),
  ];
}