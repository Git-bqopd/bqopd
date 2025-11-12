import 'package:flutter/material.dart';

class ImageViewModal extends StatefulWidget {
  final String imageUrl;
  final String? imageText;
  final String? shortCode;

  const ImageViewModal({
    super.key,
    required this.imageUrl,
    this.imageText,
    this.shortCode,
  });

  @override
  State<ImageViewModal> createState() => _ImageViewModalState();
}

class _ImageViewModalState extends State<ImageViewModal> {
  bool _isLiked = false;
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

  void _toggleShortCode() {
    setState(() {
      _showShortCode = !_showShortCode;
      _showComments = false;
      _showText = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(16), // nice side margins on desktop
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        // Prevent "RenderFlex overflowed" by capping dialog dimensions
        constraints: BoxConstraints(
          maxWidth: 1000,                   // <- side white space on large screens
          maxHeight: size.height * 0.9,     // <- keep inside viewport
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // IMAGE AREA — expands to available height but never overflows
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

              // ACTION BAR
              Material(
                elevation: 1,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border),
                        onPressed: () => setState(() => _isLiked = !_isLiked),
                        tooltip: 'Like',
                      ),
                      IconButton(
                        icon: const Icon(Icons.comment),
                        onPressed: _toggleComments,
                        tooltip: 'Comment',
                      ),
                      IconButton(
                        icon: const Icon(Icons.newspaper),
                        onPressed: _toggleText,
                        tooltip: 'Text',
                      ),
                      const Icon(Icons.remove_red_eye), // placeholder
                      const Icon(Icons.print),          // placeholder
                      IconButton(
                        icon: const Icon(Icons.link),
                        onPressed: _toggleShortCode,
                        tooltip: 'Short code',
                      ),
                    ],
                  ),
                ),
              ),

              // DETAILS AREA — becomes scrollable if tall
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

    // Wrap in SizedBox + SingleChildScrollView so long text/comments never overflow.
    return SizedBox(
      // Give the details area up to ~40% of the dialog height when needed.
      height: 240,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showComments) ...[
              const Text('Comments', style: TextStyle(fontWeight: FontWeight.w600)),
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
            if (_showShortCode) ...[
              const Text('Short Code', style: TextStyle(fontWeight: FontWeight.w600)),
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
