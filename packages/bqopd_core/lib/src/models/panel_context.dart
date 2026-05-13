import '../../bqopd_core.dart';

/// Context object used to pass data to Reader Panels.
/// This model remains in core but accepts dynamic types for Flutter-specific controllers
/// to maintain pure Dart compatibility.
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

  // Services & UI State (Abstracted from Flutter dependencies)
  final IViewService viewService;
  final IEngagementService engagementService;
  final dynamic commentController;
  final void Function()? onSubmitComment;
  final dynamic fontSizeNotifier;

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