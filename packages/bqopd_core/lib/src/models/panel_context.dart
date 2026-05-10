import 'package:flutter/material.dart';
import '../../bqopd_core.dart';

/// Context object used to pass data to Reader Panels.
/// This model remains in core but accepts Flutter-specific controllers
/// to maintain functionality in the Flutter app.
class PanelContext {
  final BonusRowType type;
  final String imageId;
  final String? fanzineId;
  final String? pageId;
  final String? templateId;
  final bool isEditingMode;
  final bool isInline;

  // Text Content
  final String actualText;
  final String textRaw;
  final String textCorrected;
  final String textLinked;
  final String textCorrectedAi;
  final String textLinkedAi;

  // Services & UI State (Passed from Flutter)
  final dynamic viewService;
  final dynamic engagementService;
  final TextEditingController? commentController;
  final VoidCallback? onSubmitComment;
  final ValueNotifier<double>? fontSizeNotifier;

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
    this.commentController,
    this.onSubmitComment,
    this.fontSizeNotifier,
  });
}