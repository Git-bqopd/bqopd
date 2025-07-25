import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
      appBar: AppBar(
        title: const Text('Fanzine Editor'),
      ),
      body: StreamBuilder<QuerySnapshot>(
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

          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 5 / 8,
              mainAxisSpacing: 8.0,
              crossAxisSpacing: 8.0,
            ),
            itemCount: pages.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return FanzineEditorWidget(fanzineId: widget.fanzineId);
              } else {
                final page = pages[index - 1];
                final pageData = page.data() as Map<String, dynamic>;
                final imageUrl = pageData['imageUrl'] ?? '';

                return DragTarget<QueryDocumentSnapshot>(
                  onWillAccept: (data) => data != null,
                  onAccept: (draggedPage) {
                    _onReorder(draggedPage, page);
                  },
                  builder: (context, candidateData, rejectedData) {
                    return Draggable<QueryDocumentSnapshot>(
                      data: page,
                      feedback: Material(
                        elevation: 4.0,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: imageUrl.isNotEmpty
                              ? Image.network(imageUrl, fit: BoxFit.cover)
                              : Container(
                                  color: Colors.grey[300],
                                  child: Center(
                                      child: Text(
                                          'Image ${pageData['pageNumber']}')),
                                ),
                        ),
                      ),
                      childWhenDragging: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300]!.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Center(
                          child: imageUrl.isNotEmpty
                              ? Image.network(imageUrl, fit: BoxFit.cover)
                              : Text('Image ${pageData['pageNumber']}'),
                        ),
                      ),
                    );
                  },
                );
              }
            },
          );
        },
      ),
    );
  }

  void _onReorder(QueryDocumentSnapshot draggedPage, QueryDocumentSnapshot targetPage) {
    final batch = FirebaseFirestore.instance.batch();
    final draggedPageData = draggedPage.data() as Map<String, dynamic>;
    final targetPageData = targetPage.data() as Map<String, dynamic>;

    final draggedPageRef = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages')
        .doc(draggedPage.id);
    final targetPageRef = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages')
        .doc(targetPage.id);

    final draggedPageNumber = draggedPageData['pageNumber'];
    final targetPageNumber = targetPageData['pageNumber'];

    batch.update(draggedPageRef, {'pageNumber': targetPageNumber});
    batch.update(targetPageRef, {'pageNumber': draggedPageNumber});

    batch.commit();
  }
}
