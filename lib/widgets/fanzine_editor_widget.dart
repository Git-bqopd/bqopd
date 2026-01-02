import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FanzineEditorWidget extends StatefulWidget {
  final String fanzineId;

  const FanzineEditorWidget({super.key, required this.fanzineId});

  @override
  State<FanzineEditorWidget> createState() => _FanzineEditorWidgetState();
}

class _FanzineEditorWidgetState extends State<FanzineEditorWidget> {
  final TextEditingController _shortcodeController = TextEditingController();

  @override
  void dispose() {
    _shortcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fanzines')
          .doc(widget.fanzineId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final fanzineData = snapshot.data!.data() as Map<String, dynamic>;
        final title = fanzineData['title'] ?? 'No Title';
        final shortCode = fanzineData['shortCode'];

        return Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // First Row: Title
              Text(title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8.0),

              // Second Row: Add Page
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _shortcodeController,
                      decoration: const InputDecoration(
                        hintText: 'Paste image shortcode',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  ElevatedButton(
                    onPressed: _addPage,
                    child: const Text('Add Page'),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),

              // Third Row: Shortcode
              SelectableText(
                shortCode != null
                    ? 'the short code is: $shortCode'
                    : 'no shortcode available.',
              ),
              const SizedBox(height: 8.0),

              // Fourth Row: Save Button
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addPage() async {
    final shortcode = _shortcodeController.text.trim();
    if (shortcode.isEmpty) {
      return;
    }

    final imageQuery = await FirebaseFirestore.instance
        .collection('images')
        .where('shortCode', isEqualTo: shortcode)
        .limit(1)
        .get();

    if (imageQuery.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image not found.')),
        );
      }
      return;
    }

    final imageDoc = imageQuery.docs.first;
    final imageData = imageDoc.data();
    final imageUrl = imageData['fileUrl'];
    final imageId = imageDoc.id;

    final pagesQuery = await FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages')
        .orderBy('pageNumber', descending: true)
        .limit(1)
        .get();

    int newPageNumber = 1;
    if (pagesQuery.docs.isNotEmpty) {
      final lastPage = pagesQuery.docs.first.data();
      newPageNumber = lastPage['pageNumber'] + 1;
    }

    final pageData = {
      'imageId': imageId,
      'imageUrl': imageUrl,
      'pageNumber': newPageNumber,
    };

    await FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages')
        .add(pageData);

    await FirebaseFirestore.instance.collection('images').doc(imageId).update({
      'usedInFanzines': FieldValue.arrayUnion([widget.fanzineId])
    });

    _shortcodeController.clear();
  }
}
