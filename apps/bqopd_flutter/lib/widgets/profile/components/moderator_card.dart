import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/panel_context.dart';
import '../../hashtag_bar.dart';
import '../../../components/dynamic_social_toolbar.dart';
import '../../reader_panels/panel_container.dart';
import '../../reader_panels/panel_factory.dart';
import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_core/bqopd_core.dart';

class ModeratorCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const ModeratorCard({
    super.key,
    required this.docId,
    required this.data,
  });

  @override
  State<ModeratorCard> createState() => _ModeratorCardState();
}

class _ModeratorCardState extends State<ModeratorCard> {
  final TextEditingController _commentController = TextEditingController();
  final EngagementService _engagementService = EngagementService();
  final ViewService _viewService = ViewService();
  final ValueNotifier<double> _fontSizeNotifier = ValueNotifier(16.0);
  BonusRowType? _activePanel;

  void _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _commentController.clear();
    await _engagementService.addComment(
      imageId: widget.docId,
      fanzineId: 'moderation_queue',
      fanzineTitle: 'Moderator Feed',
      text: text,
      displayName: userProvider.userProfile?.displayName,
      username: userProvider.userProfile?.username,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _fontSizeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.data['fileUrl'] as String?;
    final uploaderId = widget.data['uploaderId'] as String? ?? 'unknown';
    final String actualText = widget.data['text_linked'] ??
        widget.data['text_corrected'] ??
        widget.data['text_raw'] ??
        '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                height: 400,
                errorBuilder: (c, e, s) => const SizedBox(
                  height: 200,
                  child: Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Uploaded by @$uploaderId",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 8),
                HashtagBar(
                  imageId: widget.docId,
                  tags: widget.data['tags'] as Map<String, dynamic>? ?? {},
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                DynamicSocialToolbar(
                  imageId: widget.docId,
                  fanzineType: null,
                  isGame: false,
                  isEditingMode: true,
                  activeBonusRow: _activePanel,
                  onToggleBonusRow: (rowType) {
                    setState(() {
                      _activePanel = _activePanel == rowType ? null : rowType;
                    });
                  },
                ),
                if (_activePanel != null) ...[
                  const Divider(height: 1),
                  PanelContainer(
                    title: '',
                    isInline: true,
                    inlineColor: PanelFactory.getInlineColor(_activePanel!),
                    child: PanelFactory.buildPanelContent(
                      PanelContext(
                        type: _activePanel!,
                        imageId: widget.docId,
                        actualText: actualText,
                        textRaw: widget.data['text_raw'] ?? '',
                        textCorrected: widget.data['text_corrected'] ?? '',
                        textLinked: widget.data['text_linked'] ?? '',
                        textCorrectedAi: widget.data['text_corrected_ai'] ?? '',
                        textLinkedAi: widget.data['text_linked_ai'] ?? '',
                        isEditingMode: true,
                        viewService: _viewService,
                        engagementService: _engagementService,
                        commentController: _commentController,
                        onSubmitComment: _submitComment,
                        fontSizeNotifier: _fontSizeNotifier,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}