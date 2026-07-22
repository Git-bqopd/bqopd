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
      defaultIcon: 'assets/social_toolbar/open.svg',
      action: ToolAction.switchToGridView,
      condition: ToolCondition.hideOnDesktopSplit,
    ),
    // 2. Like (like)
    ReaderTool(
      id: 'Like',
      label: 'like',
      description: 'Show appreciation for the work.',
      defaultIcon: 'assets/social_toolbar/like.svg',
      activeIcon: 'assets/social_toolbar/like_FILL.svg',
      action: ToolAction.toggleLike,
    ),
    // 3. Comment (comments)
    ReaderTool(
      id: 'Comment',
      label: 'comments',
      description: 'Join the discussion on this specific page.',
      defaultIcon: 'assets/social_toolbar/comments.svg',
      activeIcon: 'assets/social_toolbar/comments_FILL.svg',
      bonusRow: BonusRowType.comments,
    ),
    // 4. Text (text)
    ReaderTool(
      id: 'Text',
      label: 'text',
      description: 'Read the finalized text.',
      defaultIcon: 'assets/social_toolbar/text.svg',
      bonusRow: BonusRowType.textReader,
    ),
    // 5. Raw (raw) - [Editor Only]
    ReaderTool(
      id: 'Raw',
      label: 'raw',
      description: 'View the raw OCR output.',
      defaultIcon: 'assets/social_toolbar/raw.svg',
      role: ToolRole.editor,
      bonusRow: BonusRowType.rawText,
    ),
    // 6. Master (edit text) - [Editor Only Combined Panel]
    ReaderTool(
      id: 'Master',
      label: 'edit text',
      description: 'Edit page text and adjust wiki-links in a unified editor.',
      defaultIcon: 'assets/social_toolbar/edit.svg',
      role: ToolRole.editor,
      bonusRow: BonusRowType.editText, // FIXED: Renamed masterText reference to editText
    ),
    // 7. Entities (entities) - [Editor Only]
    ReaderTool(
      id: 'Entities',
      label: 'entities',
      description: 'Link detected names to internal profiles.',
      defaultIcon: 'assets/social_toolbar/entities.svg',
      role: ToolRole.editor,
      condition: ToolCondition.requiresOcrPipeline,
      bonusRow: BonusRowType.entities,
    ),
    // 8. Tags (tags)
    ReaderTool(
      id: 'Tags',
      label: 'tags',
      description: 'Vote on hashtags and metadata.',
      defaultIcon: 'assets/social_toolbar/tag.svg',
      bonusRow: BonusRowType.tags,
    ),
    // 9. Indicia (indicia)
    ReaderTool(
      id: 'Indicia',
      label: 'indicia',
      description: 'View publication information and copyright details.',
      defaultIcon: 'assets/social_toolbar/indicia.svg',
      condition: ToolCondition.requiresIndicia,
      bonusRow: BonusRowType.indicia,
    ),
    // 10. Credits (credits) - [Editor Only]
    ReaderTool(
      id: 'Credits',
      label: 'credits',
      description: 'Manage archival metadata and contributor lists.',
      defaultIcon: 'assets/social_toolbar/credits.svg',
      role: ToolRole.editor,
      bonusRow: BonusRowType.credits,
    ),
    // 11. Views (views) - [Editor Only]
    ReaderTool(
      id: 'Views',
      label: 'views',
      description: 'View detailed reader analytics for this content.',
      defaultIcon: 'assets/social_toolbar/views.svg',
      role: ToolRole.editor,
      bonusRow: BonusRowType.analyticsDashboard,
    ),
    // 12. YouTube (YouTube)
    ReaderTool(
      id: 'YouTube',
      label: 'YouTube',
      description: 'Watch the video associated with this page.',
      defaultIcon: 'assets/social_toolbar/YouTube.svg',
      condition: ToolCondition.requiresYouTube,
      bonusRow: BonusRowType.youtube,
    ),
    // 13. Terminal (Terminal)
    ReaderTool(
      id: 'Terminal',
      label: 'terminal',
      description: 'Enter the terminal.',
      defaultIcon: 'assets/social_toolbar/terminal.svg',
      condition: ToolCondition.requiresGame,
      bonusRow: BonusRowType.terminal,
    ),
    // 14. Share (share)
    ReaderTool(
      id: 'Share',
      label: 'share',
      description: 'Copy a deep-link to this specific page.',
      defaultIcon: 'assets/social_toolbar/share.svg',
      action: ToolAction.openBonusRow,
      bonusRow: BonusRowType.shareOptions,
    ),
    // 15. Settings (buttons)
    ReaderTool(
      id: 'Settings',
      label: 'buttons',
      description: 'Customize which buttons appear on your toolbar.',
      defaultIcon: 'assets/social_toolbar/buttons.svg',
      bonusRow: BonusRowType.settings,
    ),
    // 16. New Page (new page) - [Editor Only Settings subrow]
    ReaderTool(
      id: 'NewPage',
      label: 'new page',
      description: 'Insert a blank 2000x3200 publisher text page.',
      defaultIcon: 'assets/social_toolbar/new_page.svg',
      role: ToolRole.editor,
      bonusRow: BonusRowType.newPage,
    ),
  ];
}