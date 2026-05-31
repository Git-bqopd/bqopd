import '../models/reader_tool.dart';

class ReaderToolsConfig {
  static bool isToolVisibleInContext({
    required ReaderTool tool,
    required String userRole,
    required bool isEditingMode,
    String? fanzineType,
    bool hasYoutube = false,
    bool isGame = false,
    bool isIndiciaPage = false,
    bool canOpenGrid = false,
  }) {
    final bool isElevated = userRole == 'admin' || userRole == 'moderator' || userRole == 'curator';
    if (tool.role == ToolRole.editor && !isElevated) return false;
    if (tool.role == ToolRole.editor && !isEditingMode) return false;

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
        if (!canOpenGrid) return false;
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
    // 1. Grid (open)
    ReaderTool(
      id: 'Grid',
      label: 'open',
      description: 'Return to the grid navigation view.',
      defaultIcon: 'menu_book',
      action: ToolAction.switchToGridView,
      condition: ToolCondition.hideOnDesktopSplit,
    ),
    // 2. Like (like)
    ReaderTool(
      id: 'Like',
      label: 'like',
      description: 'Show appreciation for the work.',
      defaultIcon: 'favorite_border',
      activeIcon: 'favorite',
      action: ToolAction.toggleLike,
    ),
    // 3. Comment (comments)
    ReaderTool(
      id: 'Comment',
      label: 'comments',
      description: 'Join the discussion on this specific page.',
      defaultIcon: 'chat_bubble_outline',
      activeIcon: 'chat_bubble',
      bonusRow: BonusRowType.comments,
    ),
    // 4. Text (text)
    ReaderTool(
      id: 'Text',
      label: 'text',
      description: 'Read the finalized text.',
      defaultIcon: 'article_outlined',
      activeIcon: 'article',
      bonusRow: BonusRowType.textReader,
    ),
    // 5. Raw (raw) - [Editor Only]
    ReaderTool(
      id: 'Raw',
      label: 'raw',
      description: 'View the raw OCR output.',
      defaultIcon: 'outdoor_grill',
      activeIcon: 'outdoor_grill',
      role: ToolRole.editor,
      bonusRow: BonusRowType.rawText,
    ),
    // 6. Master (corrected) - [Editor Only]
    ReaderTool(
      id: 'Master',
      label: 'corrected',
      description: 'Edit the corrected master text.',
      defaultIcon: 'edit_document',
      role: ToolRole.editor,
      bonusRow: BonusRowType.masterText,
    ),
    // 7. Linked (linked) - [Editor Only]
    ReaderTool(
      id: 'Linked',
      label: 'linked',
      description: 'Manually adjust wiki-links.',
      defaultIcon: 'add_link',
      role: ToolRole.editor,
      bonusRow: BonusRowType.linkedText,
    ),
    // 8. Entities (entities) - [Editor Only]
    ReaderTool(
      id: 'Entities',
      label: 'entities',
      description: 'Link detected names to internal profiles.',
      defaultIcon: 'smart_toy',
      activeIcon: 'smart_toy',
      role: ToolRole.editor,
      condition: ToolCondition.requiresOcrPipeline,
      bonusRow: BonusRowType.entities,
    ),
    // 9. Tags (tags)
    ReaderTool(
      id: 'Tags',
      label: 'tags',
      description: 'Vote on hashtags and metadata.',
      defaultIcon: 'tag',
      bonusRow: BonusRowType.tags,
    ),
    // 10. Indicia (indicia)
    ReaderTool(
      id: 'Indicia',
      label: 'indicia',
      description: 'View publication information and copyright details.',
      defaultIcon: 'info_outline',
      activeIcon: 'info',
      condition: ToolCondition.requiresIndicia,
      bonusRow: BonusRowType.indicia,
    ),
    // 11. Credits (credits) - [Editor Only]
    ReaderTool(
      id: 'Credits',
      label: 'credits',
      description: 'Manage archival metadata and contributor lists.',
      defaultIcon: 'manage_accounts_outlined',
      activeIcon: 'manage_accounts',
      role: ToolRole.editor,
      bonusRow: BonusRowType.credits,
    ),
    // 12. Views (views) - [Editor Only]
    ReaderTool(
      id: 'Views',
      label: 'views',
      description: 'View detailed reader analytics for this content.',
      defaultIcon: 'bar_chart_outlined',
      activeIcon: 'bar_chart',
      role: ToolRole.editor,
      bonusRow: BonusRowType.analyticsDashboard,
    ),
    // 13. YouTube (YouTube)
    ReaderTool(
      id: 'YouTube',
      label: 'YouTube',
      description: 'Watch the video associated with this page.',
      defaultIcon: 'play_circle_outline',
      activeIcon: 'play_circle_filled',
      condition: ToolCondition.requiresYouTube,
      bonusRow: BonusRowType.youtube,
    ),
    // 14. Terminal (Terminal)
    ReaderTool(
      id: 'Terminal',
      label: 'Terminal',
      description: 'Enter the CA Combat Terminal game experience.',
      defaultIcon: 'terminal',
      activeIcon: 'terminal',
      condition: ToolCondition.requiresGame,
      bonusRow: BonusRowType.terminal,
    ),
    // 15. Share (share)
    ReaderTool(
      id: 'Share',
      label: 'share',
      description: 'Copy a deep-link to this specific page.',
      defaultIcon: 'share_outlined',
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.shareOptions,
    ),
    // 16. Settings (buttons)
    ReaderTool(
      id: 'Settings',
      label: 'buttons',
      description: 'Customize which buttons appear on your toolbar.',
      defaultIcon: 'settings_outlined',
      activeIcon: 'settings',
      bonusRow: BonusRowType.settings,
    ),
    // 17. New Page (new page) - [Editor Only Settings subrow]
    ReaderTool(
      id: 'NewPage',
      label: 'new page',
      description: 'Insert a blank 2000x3200 publisher text page.',
      defaultIcon: 'note_add',
      activeIcon: 'note_add',
      role: ToolRole.editor,
      bonusRow: BonusRowType.newPage,
    ),
  ];
}