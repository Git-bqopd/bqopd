import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/view_service.dart';
import '../../services/engagement_service.dart';
import '../../services/user_provider.dart';
import '../../models/reader_tool.dart';
import '../../models/panel_context.dart';

import '../../components/dynamic_social_toolbar.dart';
import '../templates/calendar_template.dart';
import '../reader_panels/panel_container.dart';
import '../reader_panels/panel_factory.dart';
import '../auth_modal.dart';

/// A unified widget representing a single page in the reader.
/// Handles image/template rendering, social engagement, and inline panel logic.
class ReaderPageItem extends StatefulWidget {
  final String fanzineId;
  final String fanzineTitle;
  final Map<String, dynamic> pageData;
  final int pageIndex;

  final bool isEditingMode;
  final bool isDesktopLayout;

  final BonusRowType? activeGlobalPanel;
  final Function(BonusRowType) onTogglePanel;
  final VoidCallback? onOpenGrid; // Changed to VoidCallback

  const ReaderPageItem({
    super.key,
    required this.fanzineId,
    required this.fanzineTitle,
    required this.pageData,
    required this.pageIndex,
    required this.isEditingMode,
    required this.isDesktopLayout,
    this.activeGlobalPanel,
    required this.onTogglePanel,
    this.onOpenGrid,
  });

  @override
  State<ReaderPageItem> createState() => _ReaderPageItemState();
}

class _ReaderPageItemState extends State<ReaderPageItem> with AutomaticKeepAliveClientMixin {
  final ViewService _viewService = ViewService();
  final EngagementService _engagementService = EngagementService();
  final TextEditingController _commentController = TextEditingController();
  final ValueNotifier<double> _fontSizeNotifier = ValueNotifier(16.0);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _recordView();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _fontSizeNotifier.dispose();
    super.dispose();
  }

  void _recordView() {
    final String imageId = widget.pageData['imageId'] ?? '';
    final String pageId = widget.pageData['id'] ?? widget.pageData['__id'] ?? '';
    if (imageId.isNotEmpty) {
      _viewService.recordView(
        imageId: imageId,
        pageId: pageId,
        fanzineId: widget.fanzineId,
        fanzineTitle: widget.fanzineTitle,
        type: ViewType.list,
      );
    }
  }

  Future<void> _submitComment(String imageId) async {
    if (_commentController.text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      showDialog(context: context, builder: (c) => const AuthModal());
      return;
    }

    final text = _commentController.text.trim();
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    _commentController.clear();
    if (!widget.isDesktopLayout) FocusScope.of(context).unfocus();

    await _engagementService.addComment(
        imageId: imageId,
        fanzineId: widget.fanzineId,
        fanzineTitle: widget.fanzineTitle,
        text: text,
        displayName: userProvider.userProfile?['displayName'],
        username: userProvider.userProfile?['username']
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final String pageId = widget.pageData['id'] ?? widget.pageData['__id'] ?? '';
    final String imageId = widget.pageData['imageId'] ?? '';
    final String? templateId = widget.pageData['templateId'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 0.625,
          child: Container(
            color: Colors.grey[100],
            child: templateId == 'calendar_left'
                ? CalendarPageRenderer(isLeft: true, folioId: widget.fanzineId)
                : templateId == 'calendar_right'
                ? CalendarPageRenderer(isLeft: false, folioId: widget.fanzineId)
                : _PageImageLoader(
                imageUrl: widget.pageData['imageUrl'],
                storagePath: widget.pageData['storagePath']
            ),
          ),
        ),

        const SizedBox(height: 16),

        StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).snapshots(),
            builder: (context, fzSnapshot) {
              final fzData = fzSnapshot.data?.data() as Map<String, dynamic>?;
              final indiciaPageId = fzData?['indiciaPageId'];
              final isIndiciaPage = pageId == indiciaPageId;

              return StreamBuilder<DocumentSnapshot>(
                stream: imageId.isNotEmpty
                    ? FirebaseFirestore.instance.collection('images').doc(imageId).snapshots()
                    : null,
                builder: (context, snapshot) {
                  bool isGame = false;
                  String? youtubeId;
                  String actualText = "";

                  if (snapshot.hasData && snapshot.data?.data() != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    isGame = data['isGame'] == true;
                    youtubeId = data['youtubeId'] as String?;
                    actualText = data['text'] ?? data['text_processed'] ?? data['text_raw'] ?? '';
                  }

                  return Column(
                    children: [
                      Container(
                        color: Colors.white,
                        child: DynamicSocialToolbar(
                          imageId: imageId,
                          pageId: pageId,
                          fanzineId: widget.fanzineId,
                          pageNumber: widget.pageIndex + 1,
                          isGame: isGame,
                          youtubeId: youtubeId,
                          isEditingMode: widget.isEditingMode,
                          isIndiciaPage: isIndiciaPage,
                          onOpenGrid: widget.onOpenGrid,
                          activeBonusRow: widget.activeGlobalPanel,
                          onToggleBonusRow: widget.onTogglePanel,
                        ),
                      ),

                      if (!widget.isDesktopLayout && widget.activeGlobalPanel != null) ...[
                        const SizedBox(height: 16),
                        PanelContainer(
                          title: '',
                          isInline: true,
                          inlineColor: PanelFactory.getInlineColor(widget.activeGlobalPanel!),
                          child: PanelFactory.buildPanelContent(
                              PanelContext(
                                type: widget.activeGlobalPanel!,
                                imageId: imageId,
                                fanzineId: widget.fanzineId,
                                pageId: pageId,
                                actualText: actualText,
                                templateId: templateId,
                                isEditingMode: widget.isEditingMode,
                                viewService: _viewService,
                                engagementService: _engagementService,
                                commentController: _commentController,
                                onSubmitComment: () => _submitComment(imageId),
                                fontSizeNotifier: _fontSizeNotifier,
                                isInline: true,
                              )
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            }
        ),
      ],
    );
  }
}

class _PageImageLoader extends StatefulWidget {
  final String? imageUrl;
  final String? storagePath;

  const _PageImageLoader({this.imageUrl, this.storagePath});

  @override
  State<_PageImageLoader> createState() => _PageImageLoaderState();
}

class _PageImageLoaderState extends State<_PageImageLoader> {
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    if (widget.storagePath != null && widget.storagePath!.isNotEmpty) {
      _resolveUrl();
    } else {
      _currentUrl = widget.imageUrl;
    }
  }

  Future<void> _resolveUrl() async {
    try {
      final url = await FirebaseStorage.instance.ref(widget.storagePath!).getDownloadURL();
      if (mounted) setState(() => _currentUrl = url);
    } catch (_) {
      if (mounted) setState(() => _currentUrl = widget.imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUrl == null || _currentUrl!.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Image.network(
        _currentUrl!,
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey))
    );
  }
}