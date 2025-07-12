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
    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.network(widget.imageUrl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border),
                onPressed: () => setState(() => _isLiked = !_isLiked),
              ),
              IconButton(
                icon: const Icon(Icons.add_comment),
                onPressed: _toggleComments,
              ),
              IconButton(
                icon: const Icon(Icons.article),
                onPressed: _toggleText,
              ),
              IconButton(
                icon: const Icon(Icons.bubble_chart),
                onPressed: _toggleShortCode,
              ),
            ],
          ),
          Visibility(
            visible: _showComments,
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Leave a comment...',
                ),
              ),
            ),
          ),
          Visibility(
            visible: _showText,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(widget.imageText ?? 'No text available.'),
            ),
          ),
          Visibility(
            visible: _showShortCode,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(widget.shortCode ?? 'No shortcode available.'),
            ),
          ),
        ],
      ),
    );
  }
}
