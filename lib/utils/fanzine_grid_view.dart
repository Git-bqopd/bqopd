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
    // Step 1: try to find the fanzine by fanzines.where('shortCode' == shortCode)
    final fanzineByShortCodeStream = FirebaseFirestore.instance
        .collection('fanzines')
        .where('shortCode', isEqualTo: shortCode)
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: fanzineByShortCodeStream,
      builder: (context, fanzineSnapshot) {
        if (fanzineSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (fanzineSnapshot.hasError) {
          return Center(
            child: Text('Fanzine lookup error: ${fanzineSnapshot.error}'),
          );
        }

        String? fanzineId;

        if (fanzineSnapshot.hasData && fanzineSnapshot.data!.docs.isNotEmpty) {
          fanzineId = fanzineSnapshot.data!.docs.first.id;
          debugPrint('✅ Found fanzine by shortCode: $shortCode -> $fanzineId');
        }

        // Step 2: fallback — try resolving via /shortcodes/<shortCode>
        if (fanzineId == null) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('shortcodes')
                .doc(shortCode)
                .snapshots(),
            builder: (context, scSnap) {
              if (scSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (scSnap.hasError) {
                return Center(
                    child: Text('Shortcode error: ${scSnap.error}'));
              }
              if (!scSnap.hasData || !scSnap.data!.exists) {
                debugPrint('⚠️ No fanzine, no shortcode: $shortCode');
                return const Center(child: Text('Fanzine not found.'));
              }

              final data = scSnap.data!.data() as Map<String, dynamic>;
              final type = (data['type'] ?? '').toString();
              if (type != 'fanzine') {
                debugPrint(
                    '⚠️ Shortcode exists but not type=fanzine (type=$type)');
                return const Center(child: Text('Fanzine not found.'));
              }
              fanzineId = (data['contentId'] ?? '').toString();
              if (fanzineId == null || fanzineId!.isEmpty) {
                debugPrint('⚠️ Shortcode missing contentId');
                return const Center(child: Text('Fanzine not found.'));
              }

              debugPrint('✅ Resolved via shortcode: $shortCode -> $fanzineId');
              return _FanzinePagesGrid(
                fanzineId: fanzineId!,
                uiWidget: uiWidget,
              );
            },
          );
        }

        // If we found the fanzine in step 1, render pages
        return _FanzinePagesGrid(
          fanzineId: fanzineId!,
          uiWidget: uiWidget,
        );
      },
    );
  }
}

class _FanzinePagesGrid extends StatelessWidget {
  final String fanzineId;
  final Widget uiWidget;

  const _FanzinePagesGrid({
    required this.fanzineId,
    required this.uiWidget,
  });

  @override
  Widget build(BuildContext context) {
    // Read pages without orderBy (so we don't require a specific field)
    final pagesStream = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: pagesStream,
      builder: (context, pagesSnapshot) {
        if (pagesSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (pagesSnapshot.hasError) {
          return Center(child: Text('Error loading pages: ${pagesSnapshot.error}'));
        }

        final pagesDocs = pagesSnapshot.data?.docs ?? [];

        // Sort client-side by pageNumber, then index, then createdAt
        final pages = List<Map<String, dynamic>>.from(
          pagesDocs.map((d) => (d.data() as Map<String, dynamic>)..['_id'] = d.id),
        )..sort((a, b) {
          int aNum = (a['pageNumber'] ?? a['index'] ?? 0) as int;
          int bNum = (b['pageNumber'] ?? b['index'] ?? 0) as int;
          return aNum.compareTo(bNum);
        });

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
            if (index == 0) return uiWidget;

            final data = pages[index - 1];
            final imageUrl = (data['imageUrl'] ?? '').toString();
            final imageText = data['imageText'];
            final pageShortCode = data['shortCode'];

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
                    shortCode: pageShortCode,
                    imageId: data['_id'],
                  ),
                );
              },
              child: Image.network(imageUrl, fit: BoxFit.cover),
            );
          },
        );
      },
    );
  }
}
