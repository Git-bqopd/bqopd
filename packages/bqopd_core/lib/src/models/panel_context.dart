import '../../bqopd_core.dart';

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

  // Services & UI State
  final IViewService viewService;
  final IEngagementService engagementService;
  final dynamic commentController;
  final void Function()? onSubmitComment;
  final dynamic fontSizeNotifier; // Handled strictly via mapping in concrete views

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