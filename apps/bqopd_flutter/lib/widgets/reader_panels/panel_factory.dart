import 'package:flutter/material.dart';
import '../../models/reader_tool.dart';
import '../../models/panel_context.dart';

import 'text_reader_panel.dart';
import 'text_editor_panels.dart';
import 'hashtag_panel.dart';
import 'entities_panel.dart';
import 'youtube_panel.dart';
import 'comments_panel.dart';
import 'views_panel.dart';
import 'Credits_panel.dart';
import 'indicia_panel.dart';
import 'settings_panel.dart';

class PanelFactory {
  static String getTitle(BonusRowType type) {
    switch (type) {
      case BonusRowType.textReader: return "TEXT READER";
      case BonusRowType.rawText: return "RAW OCR TEXT";
      case BonusRowType.masterText: return "CORRECTED TEXT EDITOR";
      case BonusRowType.linkedText: return "WIKI-LINK EDITOR";
      case BonusRowType.tags: return "HASHTAGS & VOTING";
      case BonusRowType.entities: return "PAGE ENTITIES";
      case BonusRowType.comments: return "COMMENTS";
      case BonusRowType.views: return "ANALYTICS";
      case BonusRowType.credits: return "ARCHIVAL METADATA & CREDITS";
      case BonusRowType.youtube: return "VIDEO";
      case BonusRowType.indicia: return "ISSUE INDICIA";
      case BonusRowType.settings: return "SETTINGS";
      case BonusRowType.editDetails: return "EDIT DETAILS";
    }
  }

  static Color getInlineColor(BonusRowType type) {
    switch (type) {
      case BonusRowType.textReader: return const Color(0xFFFDFBF7);
      case BonusRowType.rawText: return Colors.grey[100]!;
      case BonusRowType.views: return Colors.grey[50]!;
      case BonusRowType.youtube: return Colors.black;
      default: return Colors.white;
    }
  }

  static Widget buildPanelContent(PanelContext context) {
    switch (context.type) {
      case BonusRowType.textReader:
        return TextReaderPanel(
          text: context.actualText,
          fontSizeNotifier: context.fontSizeNotifier,
        );
      case BonusRowType.rawText:
        return RawTextPanel(text: context.textRaw);
      case BonusRowType.masterText:
        return MasterTextPanel(
          imageId: context.imageId,
          initialText: context.textCorrected,
          aiBaselineText: context.textCorrectedAi,
          fanzineId: context.fanzineId ?? '',
          templateId: context.templateId,
        );
      case BonusRowType.linkedText:
        return LinkedTextPanel(
          imageId: context.imageId,
          initialText: context.textLinked,
          aiBaselineText: context.textLinkedAi,
          fanzineId: context.fanzineId ?? '',
        );
      case BonusRowType.tags:
        return HashtagPanel(imageId: context.imageId);
      case BonusRowType.entities:
        return EntitiesPanel(text: context.actualText);
      case BonusRowType.comments:
        return CommentsPanel(
          imageId: context.imageId,
          fanzineId: context.fanzineId,
          isInline: context.isInline,
        );
      case BonusRowType.views:
        return ViewsPanel(
            imageId: context.imageId,
            viewService: context.viewService);
      case BonusRowType.credits:
        return CreditsPanel(imageId: context.imageId);
      case BonusRowType.youtube:
        return YoutubePanel(imageId: context.imageId);
      case BonusRowType.indicia:
        return IndiciaPanel(
            fanzineId: context.fanzineId ?? '',
            isEditingMode: context.isEditingMode);
      case BonusRowType.settings:
        return const SettingsPanel();
      case BonusRowType.editDetails:
        return const Center(child: Text("Edit Details not implemented yet"));
    }
  }
}