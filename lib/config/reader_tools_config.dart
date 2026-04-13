import 'package:flutter/material.dart';
import '../models/reader_tool.dart';

/// Central registry for all tools available in the Reader UI.
class ReaderToolsConfig {
  static const List<ReaderTool> tools = [
    // --- PUBLIC TOOLS ---
    ReaderTool(
      id: 'Text',
      label: 'text',
      defaultIcon: Icons.article_outlined,
      activeIcon: Icons.article,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.textReader,
    ),
    ReaderTool(
      id: 'Comment',
      label: 'comments',
      defaultIcon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.comments,
    ),
    ReaderTool(
      id: 'Like',
      label: 'like',
      defaultIcon: Icons.favorite_border,
      activeIcon: Icons.favorite,
      action: ToolAction.toggleLike,
    ),
    ReaderTool(
      id: 'Share',
      label: 'share',
      defaultIcon: Icons.share_outlined,
      action: ToolAction.copyShareLink,
    ),
    ReaderTool(
      id: 'Grid',
      label: 'open',
      defaultIcon: Icons.grid_view,
      action: ToolAction.switchToGridView,
      condition: ToolCondition.hideOnDesktopSplit,
    ),
    ReaderTool(
      id: 'Settings',
      label: 'buttons',
      defaultIcon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.settings,
    ),

    // --- CONDITIONAL PUBLIC TOOLS ---
    ReaderTool(
      id: 'YouTube',
      label: 'YouTube',
      defaultIcon: Icons.play_circle_outline,
      activeIcon: Icons.play_circle_filled,
      action: ToolAction.openBonusRow,
      condition: ToolCondition.requiresYouTube,
      bonusRow: BonusRowType.youtube,
    ),
    ReaderTool(
      id: 'Tags',
      label: 'tags',
      defaultIcon: Icons.tag,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.tags,
    ),
    ReaderTool(
      id: 'Indicia',
      label: 'indicia',
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
      defaultIcon: Icons.edit_outlined,
      activeIcon: Icons.edit,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.editDetails,
    ),
    ReaderTool(
      id: 'OCR',
      label: 'ocr',
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
      defaultIcon: Icons.publish_outlined,
      activeIcon: Icons.publish,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.publisher,
    ),
    ReaderTool(
      id: 'Views',
      label: 'views',
      defaultIcon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.views,
    ),
    ReaderTool(
      id: 'Credits',
      label: 'credits',
      defaultIcon: Icons.manage_accounts_outlined,
      activeIcon: Icons.manage_accounts,
      role: ToolRole.editor,
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.credits,
    ),
  ];
}