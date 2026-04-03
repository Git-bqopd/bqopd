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
          scroll: false, // PageWrapper shouldn't scroll, CustomScrollView will
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

              // USE CustomScrollView to allow the Editor Widget at the top to be as long as it needs
              return CustomScrollView(
                slivers: [
                  // --- THE EDITOR AT THE TOP ---
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: FanzineEditorWidget(fanzineId: widget.fanzineId),
                    ),
                  ),

                  if (pages.isEmpty)
                    const SliverToBoxAdapter(
                      child: Center(
                        child: Text(
                          'No pages yet. Drag in images or create a page.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  else
                  // --- THE GRID OF PAGES BELOW ---
                    SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 5 / 8,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final page = pages[index];
                          final data = page.data() as Map<String, dynamic>;
                          final imageUrl = (data['imageUrl'] ?? '') as String?;
                          final pageNum = data['pageNumber'];

                          final tile = ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: Colors.grey[300],
                              child: imageUrl != null && imageUrl.isNotEmpty
                                  ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (c, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(child: CircularProgressIndicator());
                                },
                                errorBuilder: (c, e, s) => Center(
                                  child: Text('Image $pageNum'),
                                ),
                              )
                                  : Center(child: Text('Image $pageNum')),
                            ),
                          );

                          return DragTarget<QueryDocumentSnapshot>(
                            onWillAcceptWithDetails: (details) => details.data.id != page.id,
                            onAcceptWithDetails: (details) => _onReorder(details.data, page),
                            builder: (context, candidate, rejected) {
                              final highlight = candidate.isNotEmpty;

                              return Draggable<QueryDocumentSnapshot>(
                                data: page,
                                feedback: Opacity(
                                  opacity: 0.9,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 240),
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
                                childWhenDragging: Opacity(
                                  opacity: 0.2,
                                  child: tile,
                                ),
                                child: Container(
                                  decoration: highlight ? BoxDecoration(
                                    border: Border.all(color: Colors.amber, width: 4),
                                    borderRadius: BorderRadius.circular(12),
                                  ) : null,
                                  child: tile,
                                ),
                              );
                            },
                          );
                        },
                        childCount: pages.length,
                      ),
                    ),
                  // Bottom spacing
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
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

    if (oldPageNum == newPageNum) return;

    final batch = FirebaseFirestore.instance.batch();
    final pagesRef = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages');

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
    } else {
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

    batch.update(draggedPage.reference, {'pageNumber': newPageNum});
    await batch.commit();
  }
}