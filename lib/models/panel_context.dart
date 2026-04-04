import 'package:flutter/material.dart';
import '../services/view_service.dart';
import '../services/engagement_service.dart';
import 'reader_tool.dart';

class PanelContext {
  final BonusRowType type;
  final String imageId;
  final String? fanzineId;
  final String? pageId;
  final String actualText;
  final String? templateId;
  final bool isEditingMode;
  final bool isInline;

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
    required this.actualText,
    this.templateId,
    required this.isEditingMode,
    this.isInline = true,
    required this.viewService,
    required this.engagementService,
    required this.commentController,
    required this.onSubmitComment,
    required this.fontSizeNotifier,
  });
}