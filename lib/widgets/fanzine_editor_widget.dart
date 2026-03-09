import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/link_parser.dart';

class FanzineEditorWidget extends StatefulWidget {
  final String fanzineId;
  const FanzineEditorWidget({super.key, required this.fanzineId});

  @override
  State<FanzineEditorWidget> createState() => _FanzineEditorWidgetState();
}

class _FanzineEditorWidgetState extends State<FanzineEditorWidget> {
  final TextEditingController _shortcodeController = TextEditingController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isProcessing = false;

  @override
  void dispose() {
    _shortcodeController.dispose();
    super.dispose();
  }

  Future<void> _addPage() async {
    final shortcode = _shortcodeController.text.trim();
    if (shortcode.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final imageQuery = await _db.collection('images').where('shortCode', isEqualTo: shortcode).limit(1).get();
      if (imageQuery.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image not found.')));
        return;
      }

      final imageDoc = imageQuery.docs.first;
      final imageId = imageDoc.id;
      final imageUrl = imageDoc.data()['fileUrl'];

      final pagesQuery = await _db.collection('fanzines').doc(widget.fanzineId).collection('pages').orderBy('pageNumber', descending: true).limit(1).get();
      int nextNum = 1;
      if (pagesQuery.docs.isNotEmpty) nextNum = (pagesQuery.docs.first.data()['pageNumber'] ?? 0) + 1;

      final batch = _db.batch();
      final newPageRef = _db.collection('fanzines').doc(widget.fanzineId).collection('pages').doc();
      batch.set(newPageRef, {'imageId': imageId, 'imageUrl': imageUrl, 'pageNumber': nextNum});
      batch.update(_db.collection('images').doc(imageId), {'usedInFanzines': FieldValue.arrayUnion([widget.fanzineId])});
      await batch.commit();

      _shortcodeController.clear();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _reorderPage(DocumentSnapshot doc, int delta, List<DocumentSnapshot> allPages) async {
    final int currentPos = doc.get('pageNumber');
    final int targetPos = currentPos + delta;
    if (targetPos < 1 || targetPos > allPages.length) return;

    final targetDoc = allPages.firstWhere((p) => p.get('pageNumber') == targetPos);
    final batch = _db.batch();
    batch.update(doc.reference, {'pageNumber': targetPos});
    batch.update(targetDoc.reference, {'pageNumber': currentPos});
    await batch.commit();
  }

  Future<void> _toggleStatus(String currentStatus) async {
    final newStatus = currentStatus == 'live' ? 'working' : 'live';
    await _db.collection('fanzines').doc(widget.fanzineId).update({'status': newStatus});
  }

  Future<void> _softPublish() async {
    setState(() => _isProcessing = true);
    try {
      final allMentions = <String>{};
      final pagesSnap = await _db.collection('fanzines').doc(widget.fanzineId).collection('pages').get();
      for (final doc in pagesSnap.docs) {
        final data = doc.data();
        final imageId = data['imageId'];
        if (imageId != null) {
          final imgDoc = await _db.collection('images').doc(imageId).get();
          final text = imgDoc.data()?['text'] ?? '';
          final mentions = await LinkParser.parseMentions(text);
          allMentions.addAll(mentions);
        }
      }
      await _db.collection('fanzines').doc(widget.fanzineId).update({
        'mentionedUsers': allMentions.toList(),
        'publishedAt': FieldValue.serverTimestamp(),
        'isSoftPublished': true,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Soft Published!')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('fanzines').doc(widget.fanzineId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final title = data['title'] ?? 'Untitled';
        final shortCode = data['shortCode'] ?? 'None';
        final status = data['status'] ?? 'draft';

        return Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _shortcodeController, decoration: const InputDecoration(hintText: 'Paste image shortcode', isDense: true, border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _isProcessing ? null : _addPage, child: const Text('Add Page')),
              ]),
              const SizedBox(height: 12),
              Text('Shortcode: $shortCode', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('STATUS: ${status.toUpperCase()}', style: TextStyle(fontWeight: FontWeight.bold, color: status == 'live' ? Colors.green : Colors.orange)),
                Row(children: [
                  TextButton(onPressed: _softPublish, child: const Text('Soft Publish')),
                  Switch(value: status == 'live', onChanged: (_) => _toggleStatus(status)),
                  const Text('Live'),
                ])
              ]),
              const Divider(height: 24),
              const Text('PAGE LIST', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              _PageList(fanzineId: widget.fanzineId, onReorder: _reorderPage),
            ],
          ),
        );
      },
    );
  }
}

class _PageList extends StatelessWidget {
  final String fanzineId;
  final Function(DocumentSnapshot, int, List<DocumentSnapshot>) onReorder;
  const _PageList({required this.fanzineId, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').orderBy('pageNumber').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Text('No pages added.', style: TextStyle(color: Colors.grey, fontSize: 12));

        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final num = data['pageNumber'] ?? 0;
            final imageId = data['imageId'] ?? '...';

            return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('images').doc(imageId).get(),
                builder: (context, imgSnap) {
                  final imgTitle = (imgSnap.data?.data() as Map?)?['title'] ?? 'Page $num';
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                    child: Row(
                      children: [
                        Text('$num.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(imgTitle, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        IconButton(icon: const Icon(Icons.arrow_upward, size: 16), onPressed: () => onReorder(doc, -1, docs)),
                        IconButton(icon: const Icon(Icons.arrow_downward, size: 16), onPressed: () => onReorder(doc, 1, docs)),
                      ],
                    ),
                  );
                }
            );
          }).toList(),
        );
      },
    );
  }
}