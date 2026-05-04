import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../components/dynamic_social_toolbar.dart';
import '../models/panel_context.dart';
import '../widgets/reader_panels/panel_factory.dart';
import '../widgets/reader_panels/panel_container.dart';
import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_core/bqopd_core.dart';

class ImageViewModal extends StatefulWidget {
  final String imageUrl;
  final String? imageText;
  final String? shortCode;
  final String imageId;

  const ImageViewModal({
    super.key,
    required this.imageUrl,
    required this.imageId,
    this.imageText,
    this.shortCode,
  });

  @override
  State<ImageViewModal> createState() => _ImageViewModalState();
}

class _ImageViewModalState extends State<ImageViewModal> {
  final EngagementService _engagementService = EngagementService();
  final ViewService _viewService = ViewService();
  final TextEditingController _commentController = TextEditingController();
  final ValueNotifier<double> _fontSizeNotifier = ValueNotifier(16.0);
  BonusRowType? _activePanel;

  @override
  void dispose() {
    _commentController.dispose();
    _fontSizeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1000,
          maxHeight: size.height * 0.9,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // IMAGE AREA
              Expanded(
                child: Container(
                  color: Colors.grey[100],
                  alignment: Alignment.center,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.network(
                      widget.imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (c, e, s) => const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text('Failed to load image'),
                      ),
                    ),
                  ),
                ),
              ),

              // ACTION BAR (Using DynamicSocialToolbar)
              Material(
                elevation: 1,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('images').doc(widget.imageId).get(),
                    builder: (context, snapshot) {
                      bool isGame = false;
                      String? youtubeId;

                      if (snapshot.hasData && snapshot.data?.data() != null) {
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        isGame = data['isGame'] == true;
                        youtubeId = data['youtubeId'] as String?;
                      }

                      return DynamicSocialToolbar(
                        imageId: widget.imageId,
                        fanzineType: null,
                        isGame: isGame,
                        youtubeId: youtubeId,
                        isEditingMode: false,
                        activeBonusRow: _activePanel,
                        onToggleBonusRow: (rowType) {
                          setState(() {
                            _activePanel = _activePanel == rowType ? null : rowType;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),

              // DETAILS AREA
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                child: _buildDetailsArea(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsArea() {
    if (_activePanel == null) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('images').doc(widget.imageId).get(),
        builder: (context, snapshot) {
          String tLinked = "";
          String tCorrected = "";
          String tRaw = widget.imageText ?? '';
          String tLinkedAi = "";
          String tCorrectedAi = "";

          if (snapshot.hasData && snapshot.data?.data() != null) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            tLinked = data['text_linked'] ?? '';
            tCorrected = data['text_corrected'] ?? data['text'] ?? '';
            tRaw = data['text_raw'] ?? tRaw;
            tLinkedAi = data['text_linked_ai'] ?? '';
            tCorrectedAi = data['text_corrected_ai'] ?? '';
          }

          String actualText = tLinked.trim().isNotEmpty ? tLinked
              : (tCorrected.trim().isNotEmpty ? tCorrected : tRaw);

          return SizedBox(
            height: 240,
            child: SingleChildScrollView(
              child: PanelContainer(
                title: '',
                isInline: true,
                inlineColor: PanelFactory.getInlineColor(_activePanel!),
                child: PanelFactory.buildPanelContent(
                    PanelContext(
                      type: _activePanel!,
                      imageId: widget.imageId,
                      actualText: actualText,
                      textRaw: tRaw,
                      textCorrected: tCorrected,
                      textLinked: tLinked,
                      textCorrectedAi: tCorrectedAi, // Added
                      textLinkedAi: tLinkedAi,       // Added
                      isEditingMode: false,
                      viewService: _viewService,
                      engagementService: _engagementService,
                      commentController: _commentController,
                      onSubmitComment: () async {
                        if (_commentController.text.trim().isEmpty) return;
                        await _engagementService.addComment(
                          imageId: widget.imageId,
                          fanzineId: 'image_modal',
                          fanzineTitle: 'Image View',
                          text: _commentController.text.trim(),
                          displayName: null,
                          username: null,
                        );
                        _commentController.clear();
                      },
                      fontSizeNotifier: _fontSizeNotifier,
                    )
                ),
              ),
            ),
          );
        }
    );
  }
}