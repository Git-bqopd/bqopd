import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Opens the "Add to Fanzine" bottom sheet
  void _showAddToFanzineSheet() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          // Limit height so it doesn't cover the whole screen
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add to Fanzine',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  // Query fanzines owned by this user
                  stream: FirebaseFirestore.instance
                      .collection('fanzines')
                      .where('editorId', isEqualTo: user.uid)
                      .orderBy('creationDate', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text("You haven't created any fanzines yet."),
                      );
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final fanzineData = docs[index].data() as Map<String, dynamic>;
                        final fanzineId = docs[index].id;
                        final String title = fanzineData['title'] ?? 'Untitled Fanzine';

                        // Check if image is already in this fanzine (optional UI polish)
                        final List existingImages = fanzineData['imageIds'] ?? [];
                        final bool alreadyAdded = existingImages.contains(widget.imageId);

                        return ListTile(
                          leading: const Icon(Icons.book, color: Colors.indigo),
                          title: Text(title),
                          subtitle: Text(alreadyAdded ? 'Image already added' : 'Tap + to add'),
                          trailing: IconButton(
                            icon: Icon(
                              alreadyAdded ? Icons.check : Icons.add_circle_outline,
                              color: alreadyAdded ? Colors.green : null,
                            ),
                            onPressed: alreadyAdded
                                ? null
                                : () => _addToFanzine(fanzineId, title),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addToFanzine(String fanzineId, String fanzineTitle) async {
    try {
      final db = FirebaseFirestore.instance;

      // 1. Get the current highest page number
      final pagesQuery = await db
          .collection('fanzines')
          .doc(fanzineId)
          .collection('pages')
          .orderBy('pageNumber', descending: true)
          .limit(1)
          .get();

      int newPageNumber = 1;
      if (pagesQuery.docs.isNotEmpty) {
        final lastPage = pagesQuery.docs.first.data();
        newPageNumber = (lastPage['pageNumber'] ?? 0) + 1;
      }

      // 2. Add the actual page document (This makes it show up in the Editor!)
      await db.collection('fanzines').doc(fanzineId).collection('pages').add({
        'imageId': widget.imageId,
        'imageUrl': widget.imageUrl,
        'pageNumber': newPageNumber,
        'addedAt': FieldValue.serverTimestamp(),
      });

      // 3. Update the 'imageIds' array on the Fanzine doc (Keeps your UI checkmark working)
      await db.collection('fanzines').doc(fanzineId).update({
        'imageIds': FieldValue.arrayUnion([widget.imageId]),
      });

      if (mounted) {
        Navigator.pop(context); // Close the sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to "$fanzineTitle" as page $newPageNumber!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding to fanzine: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Check if user is logged in (an "Editor")
    final bool isEditor = FirebaseAuth.instance.currentUser != null;

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

                      // --- NEW BUTTON: ADD TO FANZINE ---
                      if (isEditor)
                        IconButton(
                          icon: const Icon(Icons.bookmark_add_outlined),
                          onPressed: _showAddToFanzineSheet,
                          tooltip: 'Add to Fanzine',
                        ),
                      // ----------------------------------

                      const Icon(Icons.print), // placeholder
                      IconButton(
                        icon: const Icon(Icons.link),
                        onPressed: _toggleShortCode,
                        tooltip: 'Short code',
                      ),
                    ],
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