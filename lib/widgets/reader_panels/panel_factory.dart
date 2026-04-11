import 'package:flutter/material.dart';
import '../../models/reader_tool.dart';
import '../../models/panel_context.dart';

import 'text_reader_panel.dart';
import 'hashtag_panel.dart';
import 'ocr_status_panel.dart';
import 'entities_panel.dart';
import 'publisher_panel.dart';
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
      case BonusRowType.tags: return "HASHTAGS & VOTING";
      case BonusRowType.ocr: return "OCR PIPELINE (EGG EDITOR)";
      case BonusRowType.entities: return "PAGE ENTITIES";
      case BonusRowType.publisher: return "PUBLISHER (CHICKEN EDITOR)";
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
      case BonusRowType.ocr:
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
          isEditingMode: context.isEditingMode,
          imageId: context.imageId,
        );
      case BonusRowType.tags:
        return HashtagPanel(imageId: context.imageId);
      case BonusRowType.ocr:
        return OcrStatusPanel(
            fanzineId: context.fanzineId ?? '',
            pageId: context.pageId ?? '',
            imageId: context.imageId);
      case BonusRowType.entities:
        return EntitiesPanel(text: context.actualText);
      case BonusRowType.publisher:
        return PublisherPanel(
          imageId: context.imageId,
          initialText: context.actualText,
          fanzineId: context.fanzineId ?? '',
          templateId: context.templateId,
        );
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