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
                  int crossAxisCount = 2;

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
                        onWillAcceptWithDetails: (details) =>
                            details.data.id != page.id,
                        onAcceptWithDetails: (details) =>
                            _onReorder(details.data, page),
                        builder: (context, candidate, rejected) {
                          final highlight = candidate.isNotEmpty;

                          final tile = ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: highlight
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : Colors.grey[300],
                              ),
                              child: imageUrl != null && imageUrl.isNotEmpty
                                  ? Image.network(
                                      imageUrl,
                                      fit: BoxFit
                                          .cover, // or BoxFit.contain if you prefer no crop
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
                                      ? Image.network(imageUrl,
                                          fit: BoxFit.cover)
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
                                color: Colors.grey[300]!.withValues(alpha: 0.5),
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

  Future<void> _onReorder(
    QueryDocumentSnapshot draggedPage,
    QueryDocumentSnapshot targetPage,
  ) async {
    final draggedData = draggedPage.data() as Map<String, dynamic>;
    final targetData = targetPage.data() as Map<String, dynamic>;

    final int oldPageNum = draggedData['pageNumber'];
    final int newPageNum = targetData['pageNumber'];

    // If dropped on itself, do nothing
    if (oldPageNum == newPageNum) return;

    final batch = FirebaseFirestore.instance.batch();
    final pagesRef = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages');

    // CASE 1: Dragging Down (e.g., Page 1 -> Page 3)
    // We need to shift pages (1 < p <= 3) DOWN by 1 (decrement their pageNumber)
    // so Page 2 becomes 1, Page 3 becomes 2, and dragged Item takes spot 3.
    if (oldPageNum < newPageNum) {
      final query = await pagesRef
          .where('pageNumber', isGreaterThan: oldPageNum)
          .where('pageNumber', isLessThanOrEqualTo: newPageNum)
          .get();

      for (final doc in query.docs) {
        batch.update(doc.reference, {
          'pageNumber': FieldValue.increment(-1),
        });
      }
    }
    // CASE 2: Dragging Up (e.g., Page 3 -> Page 1)
    // We need to shift pages (1 <= p < 3) UP by 1 (increment their pageNumber)
    // so Page 1 becomes 2, Page 2 becomes 3, and dragged Item takes spot 1.
    else {
      final query = await pagesRef
          .where('pageNumber', isGreaterThanOrEqualTo: newPageNum)
          .where('pageNumber', isLessThan: oldPageNum)
          .get();

      for (final doc in query.docs) {
        batch.update(doc.reference, {
          'pageNumber': FieldValue.increment(1),
        });
      }
    }

    // Finally, set the dragged page to the new target number
    batch.update(draggedPage.reference, {'pageNumber': newPageNum});

    await batch.commit();
  }
}
