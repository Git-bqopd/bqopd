import 'package:flutter/material.dart';
import '../../models/reader_tool.dart';
import '../../models/panel_context.dart';
import '../../services/view_service.dart';
import '../../services/engagement_service.dart';

import 'text_reader_panel.dart';
import 'hashtag_panel.dart';
import 'ocr_status_panel.dart';
import 'entities_panel.dart';
import 'publisher_panel.dart';
import 'youtube_panel.dart';
import 'comments_panel.dart';
import 'views_panel.dart';
import 'credits_panel.dart';
import 'indicia_panel.dart';
import 'settings_panel.dart';

class PanelFactory {
  /// Returns the standardized header title for the Desktop Sidebar view
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

  /// Returns the specific background color for the inline mobile view
  static Color getInlineColor(BonusRowType type) {
    switch (type) {
      case BonusRowType.textReader: return const Color(0xFFFDFBF7);
      case BonusRowType.ocr:
      case BonusRowType.views: return Colors.grey[50]!;
      case BonusRowType.youtube: return Colors.black;
      default: return Colors.white;
    }
  }

  /// Acts as the routing switchboard to build the requested panel content
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
          engagementService: context.engagementService,
          controller: context.commentController,
          onSend: context.onSubmitComment,
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