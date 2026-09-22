import '../models/reader_tool.dart';

class ReaderToolsConfig {
  static bool isToolVisibleInContext({
    required ReaderTool tool,
    required ToolScope activeScope,
    String? fanzineType,
    bool hasYoutube = false,
    bool isGame = false,
    bool isIndiciaPage = false,
    bool canOpenGrid = false,
  }) {
    if (!tool.scopes.contains(activeScope)) return false;

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
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
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
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      action: ToolAction.toggleLike,
    ),
    // 3. Comment (comments)
    ReaderTool(
      id: 'Comment',
      label: 'comments',
      description: 'Join the discussion on this specific page.',
      defaultIcon: 'assets/social_toolbar/comments.svg',
      activeIcon: 'assets/social_toolbar/comments_FILL.svg',
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      readerBonusRow: BonusRowType.comments,
      editorBonusRow: BonusRowType.comments,
      curatorBonusRow: BonusRowType.comments,
      readerBonusColumn: BonusRowType.comments,
      editorBonusColumn: BonusRowType.comments,
      curatorBonusColumn: BonusRowType.comments,
    ),
    // 4. Text (text)
    ReaderTool(
      id: 'Text',
      label: 'text',
      description: 'Read the finalized text.',
      defaultIcon: 'assets/social_toolbar/text.svg',
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      readerBonusRow: BonusRowType.textReader,
      editorBonusRow: BonusRowType.textReader,
      curatorBonusRow: BonusRowType.textReader,
      readerBonusColumn: BonusRowType.textReader,
      editorBonusColumn: BonusRowType.textReader,
      curatorBonusColumn: BonusRowType.textReader,
    ),
    // 5. Raw (raw)
    ReaderTool(
      id: 'Raw',
      label: 'raw',
      description: 'View the raw OCR output.',
      defaultIcon: 'assets/social_toolbar/raw.svg',
      scopes: const {ToolScope.editor, ToolScope.curator},
      editorBonusRow: BonusRowType.rawText,
      curatorBonusRow: BonusRowType.rawText,
      editorBonusColumn: BonusRowType.rawText,
      curatorBonusColumn: BonusRowType.rawText,
    ),
    // 6. Master (edit text)
    ReaderTool(
      id: 'Master',
      label: 'edit text',
      description: 'Edit page text and adjust wiki-links in a unified editor.',
      defaultIcon: 'assets/social_toolbar/edit.svg',
      scopes: const {ToolScope.editor, ToolScope.curator},
      editorBonusRow: BonusRowType.editText,
      curatorBonusRow: BonusRowType.editText,
      editorBonusColumn: BonusRowType.editText,
      curatorBonusColumn: BonusRowType.editText,
    ),
    // 7. Entities (entities)
    ReaderTool(
      id: 'Entities',
      label: 'entities',
      description: 'Link detected names to internal profiles.',
      defaultIcon: 'assets/social_toolbar/entities.svg',
      scopes: const {ToolScope.reader, ToolScope.curator},
      condition: ToolCondition.requiresOcrPipeline,
      readerBonusRow: BonusRowType.entities,
      curatorBonusRow: BonusRowType.entities,
      readerBonusColumn: BonusRowType.entities,
      curatorBonusColumn: BonusRowType.entities,
    ),
    // 8. Tags (tags)
    ReaderTool(
      id: 'Tags',
      label: 'tags',
      description: 'Vote on hashtags and metadata.',
      defaultIcon: 'assets/social_toolbar/tag.svg',
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      readerBonusRow: BonusRowType.tags,
      editorBonusRow: BonusRowType.tags,
      curatorBonusRow: BonusRowType.tags,
      readerBonusColumn: BonusRowType.tags,
      editorBonusColumn: BonusRowType.tags,
      curatorBonusColumn: BonusRowType.tags,
    ),
    // 9. Indicia (indicia)
    ReaderTool(
      id: 'Indicia',
      label: 'indicia',
      description: 'View publication information and copyright details.',
      defaultIcon: 'assets/social_toolbar/indicia.svg',
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      condition: ToolCondition.requiresIndicia,
      readerBonusRow: BonusRowType.indicia,
      editorBonusRow: BonusRowType.indicia,
      curatorBonusRow: BonusRowType.indicia,
      readerBonusColumn: BonusRowType.indicia,
      editorBonusColumn: BonusRowType.indicia,
      curatorBonusColumn: BonusRowType.indicia,
    ),
    // 10. Credits (credits)
    ReaderTool(
      id: 'Credits',
      label: 'credits',
      description: 'Manage archival metadata and contributor lists.',
      defaultIcon: 'assets/social_toolbar/credits.svg',
      scopes: const {ToolScope.editor, ToolScope.curator},
      editorBonusRow: BonusRowType.credits,
      curatorBonusRow: BonusRowType.credits,
      editorBonusColumn: BonusRowType.credits,
      curatorBonusColumn: BonusRowType.credits,
    ),
    // 11. Views (views)
    ReaderTool(
      id: 'Views',
      label: 'views',
      description: 'View detailed reader analytics for this content.',
      defaultIcon: 'assets/social_toolbar/views.svg',
      scopes: const {ToolScope.editor, ToolScope.curator},
      editorBonusRow: BonusRowType.analyticsDashboard,
      curatorBonusRow: BonusRowType.analyticsDashboard,
      editorBonusColumn: BonusRowType.analyticsDashboard,
      curatorBonusColumn: BonusRowType.analyticsDashboard,
    ),
    // 12. YouTube (YouTube)
    ReaderTool(
      id: 'YouTube',
      label: 'YouTube',
      description: 'Watch the video associated with this page.',
      defaultIcon: 'assets/social_toolbar/YouTube.svg',
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      condition: ToolCondition.requiresYouTube,
      readerBonusRow: BonusRowType.youtube,
      editorBonusRow: BonusRowType.youtube,
      curatorBonusRow: BonusRowType.youtube,
      readerBonusColumn: BonusRowType.youtube,
      editorBonusColumn: BonusRowType.youtube,
      curatorBonusColumn: BonusRowType.youtube,
    ),
    // 13. Terminal (Terminal)
    ReaderTool(
      id: 'Terminal',
      label: 'terminal',
      description: 'Enter the terminal.',
      defaultIcon: 'assets/social_toolbar/terminal.svg',
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      condition: ToolCondition.requiresGame,
      readerBonusRow: BonusRowType.terminal,
      editorBonusRow: BonusRowType.terminal,
      curatorBonusRow: BonusRowType.terminal,
      readerBonusColumn: BonusRowType.terminal,
      editorBonusColumn: BonusRowType.terminal,
      curatorBonusColumn: BonusRowType.terminal,
    ),
    // 14. Share (share)
    ReaderTool(
      id: 'Share',
      label: 'share',
      description: 'Copy a deep-link to this specific page.',
      defaultIcon: 'assets/social_toolbar/share.svg',
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      action: ToolAction.copyShareLink,
    ),
    // 15. Settings (buttons)
    ReaderTool(
      id: 'Settings',
      label: 'buttons',
      description: 'Customize which buttons appear on your toolbar.',
      defaultIcon: 'assets/social_toolbar/buttons.svg',
      scopes: const {ToolScope.reader, ToolScope.editor, ToolScope.curator},
      readerBonusRow: BonusRowType.settings,
      editorBonusRow: BonusRowType.settings,
      curatorBonusRow: BonusRowType.settings,
      readerBonusColumn: BonusRowType.settings,
      editorBonusColumn: BonusRowType.settings,
      curatorBonusColumn: BonusRowType.settings,
    ),
    // 16. New Page (new page)
    ReaderTool(
      id: 'NewPage',
      label: 'new page',
      description: 'Insert a blank 2000x3200 publisher text page.',
      defaultIcon: 'assets/social_toolbar/new_page.svg',
      scopes: const {ToolScope.editor},
      editorBonusRow: BonusRowType.newPage,
      editorBonusColumn: BonusRowType.newPage,
    ),
  ];
}