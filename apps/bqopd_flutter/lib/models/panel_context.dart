import 'package:flutter/material.dart';
import '../services/view_service.dart';
import '../services/engagement_service.dart';
import 'reader_tool.dart';

class PanelContext {
  final BonusRowType type;
  final String imageId;
  final String? fanzineId;
  final String? pageId;
  final String? templateId;
  final bool isEditingMode;
  final bool isInline;

  // Granular Text States
  final String actualText; // The best available text to read
  final String textRaw;
  final String textCorrected;
  final String textLinked;

  // AI Baselines for Scoring
  final String textCorrectedAi;
  final String textLinkedAi;

  // Services & State
  final ViewService viewService;
  final EngagementService engagementService;
  final TextEditingController commentController;
  final VoidCallback onSubmitComment;
  final ValueNotifier<double> fontSizeNotifier;

  PanelContext({
    required this.type,
    required this.imageId,
    this.fanzineId,
    this.pageId,
    this.templateId,
    required this.isEditingMode,
    this.isInline = true,
    required this.actualText,
    required this.textRaw,
    required this.textCorrected,
    required this.textLinked,
    required this.textCorrectedAi,
    required this.textLinkedAi,
    required this.viewService,
    required this.engagementService,
    required this.commentController,
    required this.onSubmitComment,
    required this.fontSizeNotifier,
  });
}