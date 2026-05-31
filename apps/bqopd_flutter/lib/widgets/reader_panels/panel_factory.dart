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
import 'publisher_panel.dart'; // Added publisher_panel import

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
      case BonusRowType.analyticsDashboard: return "EXTENDED ANALYTICS";
      case BonusRowType.shareOptions: return "SHARE PAGE";
      case BonusRowType.credits: return "ARCHIVAL METADATA & CREDITS";
      case BonusRowType.youtube: return "VIDEO";
      case BonusRowType.indicia: return "ISSUE INDICIA";
      case BonusRowType.settings: return "SETTINGS";
      case BonusRowType.editDetails: return "EDIT DETAILS";
      case BonusRowType.terminal: return "COMBAT TERMINAL";
      case BonusRowType.newPage: return "PUBLISHER EDITOR"; // Matched newPage case
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
      case BonusRowType.newPage: return Colors.white; // Added
      default: return Colors.white;
    }
  }

  static Widget buildPanelContent(PanelContext context) {
    // Safely parse the value notifier out from dynamic wrapper
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
      case BonusRowType.masterText:
        return MasterTextPanel(
          imageId: context.imageId,
          initialText: context.textCorrected,
          fanzineId: context.fanzineId ?? '',
          templateId: context.templateId,
          aiBaselineText: context.textCorrectedAi,
        );
      case BonusRowType.linkedText:
        return LinkedTextPanel(
          imageId: context.imageId,
          initialText: context.textLinked,
          fanzineId: context.fanzineId ?? '',
          aiBaselineText: context.textLinkedAi,
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
                  onPressed: () { /* Sharing logic */ },
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text("Copy Direct Link"),
                )
              ],
            ),
          ),
        );
      case BonusRowType.credits:
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
      case BonusRowType.newPage: // Matched newPage case
        return PublisherPanel(
          imageId: context.imageId,
          initialText: context.actualText,
          fanzineId: context.fanzineId ?? '',
          templateId: context.templateId,
        );
    }
  }
}