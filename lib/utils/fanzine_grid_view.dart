import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/image_view_modal.dart';

class FanzineGridView extends StatelessWidget {
  final String shortCode;
  final Widget uiWidget;

  const FanzineGridView({
    super.key,
    required this.shortCode,
    required this.uiWidget,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fanzines')
          .where('shortCode', isEqualTo: shortCode)
          .limit(1)
          .snapshots(),
      builder: (context, fanzineSnapshot) {
        if (fanzineSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!fanzineSnapshot.hasData || fanzineSnapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Fanzine not found.'));
        }

        final fanzineId = fanzineSnapshot.data!.docs.first.id;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('fanzines')
              .doc(fanzineId)
              .collection('pages')
              .orderBy('pageNumber')
              .snapshots(),
          builder: (context, pagesSnapshot) {
            if (pagesSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (pagesSnapshot.hasError) {
              return const Center(child: Text('Error loading pages.'));
            }

            final pages = pagesSnapshot.data?.docs ?? [];

            return GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 5 / 8,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
              ),
              itemCount: pages.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return uiWidget;
                }
                final page = pages[index - 1];
                final data = page.data() as Map<String, dynamic>;
                final imageUrl = data['imageUrl'] ?? '';
                final imageText = data['imageText'];
                final shortCode = data['shortCode'];

                if (imageUrl.isEmpty) {
                  return Container(color: Colors.grey[300]);
                }

                return GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => ImageViewModal(
                        imageUrl: imageUrl,
                        imageText: imageText,
                        shortCode: shortCode,
                      ),
                    );
                  },
                  child: Image.network(imageUrl, fit: BoxFit.cover),
                );
              },
            );
          },
        );
      },
    );
  }
}

