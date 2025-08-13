import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/guard_write.dart';

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
  final TextEditingController _commentController = TextEditingController();

  void _toggleComments() {
    setState(() {
      _showComments = !_showComments;
      _showText = false;
      _showShortCode = false;
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final intent = consumePendingIntent();
    final postId = widget.shortCode ?? widget.imageUrl;
    if (intent != null) {
      if (intent.action == 'like' && intent.extras?['postId'] == postId) {
        _toggleLike();
      } else if (intent.action == 'comment' && intent.extras?['postId'] == postId) {
        final text = intent.extras?['comment'];
        if (text != null) {
          _postComment(text);
        }
      }
    }
  }

  Future<void> _toggleLike() async {
    final postId = widget.shortCode ?? widget.imageUrl;
    await guardWrite(context, () async {
      final user = FirebaseAuth.instance.currentUser!;
      final docId = '${postId}_${user.uid}';
      final doc = FirebaseFirestore.instance.collection('likes').doc(docId);
      final snap = await doc.get();
      if (snap.exists) {
        await doc.delete();
        if (mounted) setState(() => _isLiked = false);
      } else {
        await doc.set({
          'postId': postId,
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) setState(() => _isLiked = true);
      }
    }, action: 'like', extras: {'postId': postId});
  }

  Future<void> _postComment(String text) async {
    final postId = widget.shortCode ?? widget.imageUrl;
    await guardWrite(context, () async {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance.collection('comments').add({
        'postId': postId,
        'uid': user.uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _commentController.clear();
    }, action: 'comment', extras: {'postId': postId, 'comment': text});
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
                onPressed: _toggleLike,
              ),
              IconButton(
                icon: const Icon(Icons.comment),
                onPressed: _toggleComments,
              ),
              IconButton(
                icon: const Icon(Icons.newspaper),
                onPressed: _toggleText,
              ),
              Icon(Icons.remove_red_eye),
              Icon(Icons.print),
              IconButton(
                icon: const Icon(Icons.link),
                onPressed: _toggleShortCode,
              ),
            ],
          ),
          Visibility(
            visible: _showComments,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        hintText: 'leave a comment...',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      final text = _commentController.text.trim();
                      if (text.isNotEmpty) {
                        _postComment(text);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          Visibility(
            visible: _showText,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(widget.imageText ?? 'no text available.'),
            ),
          ),
          Visibility(
            visible: _showShortCode,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(
                widget.shortCode != null
                    ? 'the short code is: ${widget.shortCode}'
                    : 'no shortcode available.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
