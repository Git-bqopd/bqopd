import 'package:flutter/material.dart';
import '../components/social_toolbar.dart'; // Updated import

class ImageViewModal extends StatefulWidget {
  final String imageUrl;
  final String? imageText;
  final String? shortCode;
  final String imageId; // REQUIRED: Need this to save reference to DB

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
  bool _showComments = false;
  bool _showText = false;
  bool _showShortCode = false;

  void _toggleComments() {
    setState(() {
      _showComments = !_showComments;
      _showText = false;
      _showShortCode = false;
    });
  }

  void _toggleText() {
    setState(() {
      _showText = !_showText;
      _showComments = false;
      _showShortCode = false;
    });
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

              // ACTION BAR (Using SocialToolbar)
              Material(
                elevation: 1,
                color: Colors.white,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: SocialToolbar(
                    imageId: widget.imageId,
                    onToggleComments: _toggleComments,
                    onToggleText: _toggleText,
                    // Note: 'Open' button won't appear as we don't pass onOpenGrid
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
    final showAnything = _showComments || _showText || _showShortCode;
    if (!showAnything) return const SizedBox.shrink();

    return SizedBox(
      height: 240,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showComments) ...[
              const Text('Comments',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const TextField(
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'leave a comment...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_showText) ...[
              const Text('Text', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(widget.imageText ?? 'no text available.'),
              const SizedBox(height: 16),
            ],
            // Keep ShortCode display for now if triggered manually,
            // though SocialToolbar doesn't trigger it yet.
            if (_showShortCode) ...[
              const Text('Short Code',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SelectableText(
                widget.shortCode != null
                    ? 'the short code is: ${widget.shortCode}'
                    : 'no shortcode available.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
