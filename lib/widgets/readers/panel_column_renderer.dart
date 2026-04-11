import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/view_service.dart';
import '../../services/engagement_service.dart';
import '../../services/user_provider.dart';
import '../../models/reader_tool.dart';
import '../../models/panel_context.dart';

import '../reader_panels/panel_container.dart';
import '../reader_panels/panel_factory.dart';
import '../auth_modal.dart';

class PanelColumnRenderer extends StatelessWidget {
  final String fanzineId;
  final String fanzineTitle;
  final List<Map<String, dynamic>> pages;
  final BonusRowType activePanel;
  final ViewService viewService;
  final bool isEditingMode;
  final ItemScrollController itemScrollController;
  final VoidCallback onClose;

  const PanelColumnRenderer({
    super.key,
    required this.fanzineId,
    required this.fanzineTitle,
    required this.pages,
    required this.activePanel,
    required this.viewService,
    required this.isEditingMode,
    required this.itemScrollController,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                PanelFactory.getTitle(activePanel),
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        // List
        Expanded(
          child: ScrollablePositionedList.separated(
            itemScrollController: itemScrollController,
            itemCount: pages.length,
            separatorBuilder: (_, __) => const Divider(height: 32, thickness: 4, color: Colors.black12),
            itemBuilder: (context, index) {
              final pageData = pages[index];
              return _PanelColumnItem(
                pageData: pageData,
                pageIndex: index,
                fanzineId: fanzineId,
                fanzineTitle: fanzineTitle,
                activePanel: activePanel,
                viewService: viewService,
                isEditingMode: isEditingMode,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PanelColumnItem extends StatefulWidget {
  final Map<String, dynamic> pageData;
  final int pageIndex;
  final String fanzineId;
  final String fanzineTitle;
  final BonusRowType activePanel;
  final ViewService viewService;
  final bool isEditingMode;

  const _PanelColumnItem({
    required this.pageData,
    required this.pageIndex,
    required this.fanzineId,
    required this.fanzineTitle,
    required this.activePanel,
    required this.viewService,
    required this.isEditingMode,
  });

  @override
  State<_PanelColumnItem> createState() => _PanelColumnItemState();
}

class _PanelColumnItemState extends State<_PanelColumnItem> with AutomaticKeepAliveClientMixin {
  final EngagementService _engagementService = EngagementService();
  final TextEditingController _commentController = TextEditingController();
  final ValueNotifier<double> _fontSizeNotifier = ValueNotifier(16.0);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _commentController.dispose();
    _fontSizeNotifier.dispose();
    super.dispose();
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
    FocusScope.of(context).unfocus();

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
    final int pageNum = widget.pageData['pageNumber'] ?? (widget.pageIndex + 1);

    if (imageId.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text("Page $pageNum: No image data.", style: const TextStyle(color: Colors.grey)),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('images').doc(imageId).snapshots(),
      builder: (context, snapshot) {
        String actualText = "";
        if (snapshot.hasData && snapshot.data?.data() != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          actualText = data['text'] ?? data['text_processed'] ?? data['text_raw'] ?? '';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text("PAGE $pageNum", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            PanelContainer(
              title: '', // Header is handled by the main column container now
              isInline: false, // Ensures it behaves predictably in a layout
              child: PanelFactory.buildPanelContent(
                  PanelContext(
                    type: widget.activePanel,
                    imageId: imageId,
                    fanzineId: widget.fanzineId,
                    pageId: pageId,
                    actualText: actualText,
                    templateId: templateId,
                    isEditingMode: widget.isEditingMode,
                    viewService: widget.viewService,
                    engagementService: _engagementService,
                    commentController: _commentController,
                    onSubmitComment: () => _submitComment(imageId),
                    fontSizeNotifier: _fontSizeNotifier,
                    isInline: false,
                  )
              ),
            ),
          ],
        );
      },
    );
  }
}