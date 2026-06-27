import 'package:bqopd_core/bqopd_core.dart';
import 'package:flutter/material.dart';
import '../../services/engagement_service.dart';
import '../../services/view_service.dart';
import '../../game/game_lobby.dart';
import 'comments_panel.dart';
import 'credits_panel.dart';
import 'entities_panel.dart';
import 'hashtag_panel.dart';
import 'indicia_panel.dart';
import 'settings_panel.dart';
import 'text_editor_panels.dart';
import 'text_reader_panel.dart';
import 'views_panel.dart';
import 'youtube_panel.dart';
import 'publisher_panel.dart';

class PanelFactory {
  static String getTitle(BonusRowType type) {
    switch (type) {
      case BonusRowType.textReader: return "TEXT READER";
      case BonusRowType.rawText: return "RAW OCR TEXT";
      case BonusRowType.editText: return "EDIT TEXT"; // FIXED: Uses matching editText enum name
      case BonusRowType.linkedText: return "EDIT TEXT"; // Backwards compatibility fallback mapping
      case BonusRowType.tags: return "HASHTAGS & VOTING";
      case BonusRowType.entities: return "PAGE ENTITIES";
      case BonusRowType.comments: return "COMMENTS";
      case BonusRowType.views: return "ANALYTICS";
      case BonusRowType.analyticsDashboard: return "EXTENDED ANALYTICS";
      case BonusRowType.shareOptions: return "SHARE PAGE";
      case BonusRowType.credits: return "ARCHIVAL METADATA & CREDITS";
      case BonusRowType.youtube: return "VIDEO";
      case BonusRowType.indicia: return "ISSUE INDICIA";
      case BonusRowType.settings: return "SETTINGS";
      case BonusRowType.editDetails: return "EDIT DETAILS";
      case BonusRowType.terminal: return "COMBAT TERMINAL";
      case BonusRowType.newPage: return "PUBLISHER EDITOR";
    }
  }

  static Color getInlineColor(BonusRowType type) {
    switch (type) {
      case BonusRowType.textReader: return const Color(0xFFFDFBF7);
      case BonusRowType.rawText: return Colors.grey[100]!;
      case BonusRowType.views: return Colors.grey[50]!;
      case BonusRowType.youtube: return Colors.black;
      case BonusRowType.shareOptions: return Colors.indigo.withValues(alpha: 0.05);
      case BonusRowType.terminal: return const Color(0xFF0D0D0D);
      case BonusRowType.newPage: return Colors.white;
      default: return Colors.white;
    }
  }

  static Widget buildPanelContent(PanelContext context) {
    final ValueNotifier<double> resolvedSizeNotifier =
    (context.fontSizeNotifier is ValueNotifier<double>)
        ? context.fontSizeNotifier as ValueNotifier<double>
        : ValueNotifier<double>(16.0);

    switch (context.type) {
      case BonusRowType.textReader:
        return TextReaderPanel(
          text: context.actualText,
          fontSizeNotifier: resolvedSizeNotifier,
        );
      case BonusRowType.rawText:
        return RawTextPanel(text: context.textRaw);
      case BonusRowType.editText: // FIXED: Map to the editText enum key
      case BonusRowType.linkedText: // Route link panels straight to the unified master editor!
        return EditTextPanel(
          imageId: context.imageId,
          // FIXED: Prioritize actualText (which is pre-resolved to textLinked) instead of textCorrected!
          initialText: context.actualText,
          fanzineId: context.fanzineId ?? '',
          templateId: context.templateId,
          aiBaselineText: context.textCorrectedAi,
        );
      case BonusRowType.tags:
        return HashtagPanel(imageId: context.imageId);
      case BonusRowType.entities:
        return EntitiesPanel(text: context.actualText);
      case BonusRowType.comments:
        return CommentsPanel(
            imageId: context.imageId,
            fanzineId: context.fanzineId,
            isInline: context.isInline
        );
      case BonusRowType.views:
      case BonusRowType.analyticsDashboard:
        return ViewsPanel(
            imageId: context.imageId,
            viewService: context.viewService as ViewService
        );
      case BonusRowType.shareOptions:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const Text("Select how you'd like to share this page.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text("Copy Direct Link"),
                )
              ],
            ),
          ),
        );
      case BonusRowType.credits: // FIXED: Cleaned up the non-existent focusedPanel case reference
        return CreditsPanel(imageId: context.imageId);
      case BonusRowType.youtube:
        return YoutubePanel(imageId: context.imageId);
      case BonusRowType.indicia:
        return IndiciaPanel(
            fanzineId: context.fanzineId ?? '',
            isEditingMode: context.isEditingMode
        );
      case BonusRowType.settings:
        return const SettingsPanel();
      case BonusRowType.editDetails:
        return const Center(child: Text("Edit Details not implemented yet"));
      case BonusRowType.terminal:
        return const GameLobby();
      case BonusRowType.newPage:
        return PublisherPanel(
          imageId: context.imageId,
          initialText: context.actualText,
          fanzineId: context.fanzineId ?? '',
          templateId: context.templateId,
        );
    }
  }
}