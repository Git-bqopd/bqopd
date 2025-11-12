import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/fanzine_editor_widget.dart';

class FanzineEditorPage extends StatefulWidget {
  final String fanzineId;

  const FanzineEditorPage({super.key, required this.fanzineId});

  @override
  State<FanzineEditorPage> createState() => _FanzineEditorPageState();
}

class _FanzineEditorPageState extends State<FanzineEditorPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: false, // ✅ child is GridView (already scrollable)
          padding: const EdgeInsets.all(8),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('fanzines')
                .doc(widget.fanzineId)
                .collection('pages')
                .orderBy('pageNumber')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('Error loading pages.'));
              }

              final pages = snapshot.data?.docs ?? [];
              if (pages.isEmpty) {
                return ListView(
                  children: [
                    // Keep scroll feel consistent even when empty
                    FanzineEditorWidget(fanzineId: widget.fanzineId),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'No pages yet. Drag in images or create a page.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ],
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  // Simple responsive breakpoints
                  final width = constraints.maxWidth;
                  int crossAxisCount = 2;
                  if (width >= 1200) crossAxisCount = 4;
                  else if (width >= 900) crossAxisCount = 3;

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 5 / 8,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: pages.length + 1, // +1 for editor widget
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return FanzineEditorWidget(fanzineId: widget.fanzineId);
                      }

                      final page = pages[index - 1];
                      final data = page.data() as Map<String, dynamic>;
                      final imageUrl = (data['imageUrl'] ?? '') as String?;
                      final pageNum = data['pageNumber'];

                      return DragTarget<QueryDocumentSnapshot>(
                        onWillAccept: (incoming) => incoming != null,
                        onAccept: (draggedPage) => _onReorder(draggedPage, page),
                        builder: (context, candidate, rejected) {
                          final highlight = candidate.isNotEmpty;

                          final tile = ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: highlight
                                    ? Colors.amber.withOpacity(0.2)
                                    : Colors.grey[300],
                              ),
                              child: imageUrl != null && imageUrl.isNotEmpty
                                  ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover, // or BoxFit.contain if you prefer no crop
                                loadingBuilder: (c, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(
                                      child: CircularProgressIndicator());
                                },
                                errorBuilder: (c, e, s) => Center(
                                  child: Text('Image $pageNum'),
                                ),
                              )
                                  : Center(child: Text('Image $pageNum')),
                            ),
                          );

                          return Draggable<QueryDocumentSnapshot>(
                            data: page,
                            feedback: Opacity(
                              opacity: 0.9,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 240, // reasonable preview size
                                ),
                                child: Material(
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(12),
                                  clipBehavior: Clip.antiAlias,
                                  child: imageUrl != null && imageUrl.isNotEmpty
                                      ? Image.network(imageUrl, fit: BoxFit.cover)
                                      : Container(
                                    color: Colors.grey[300],
                                    padding: const EdgeInsets.all(12),
                                    child: Text('Image $pageNum'),
                                  ),
                                ),
                              ),
                            ),
                            childWhenDragging: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                color: Colors.grey[300]!.withOpacity(0.5),
                              ),
                            ),
                            child: tile,
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _onReorder(
      QueryDocumentSnapshot draggedPage,
      QueryDocumentSnapshot targetPage,
      ) {
    final batch = FirebaseFirestore.instance.batch();

    final draggedData = draggedPage.data() as Map<String, dynamic>;
    final targetData = targetPage.data() as Map<String, dynamic>;

    final draggedRef = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages')
        .doc(draggedPage.id);

    final targetRef = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages')
        .doc(targetPage.id);

    batch.update(draggedRef, {'pageNumber': targetData['pageNumber']});
    batch.update(targetRef, {'pageNumber': draggedData['pageNumber']});

    batch.commit();
  }
}
