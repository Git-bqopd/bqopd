import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../image_view_modal.dart';
import 'profile_helpers.dart';
import 'package:bqopd_state/bqopd_state.dart';

class MakerItemTile extends StatelessWidget {
  final dynamic doc; // DocumentSnapshot
  final bool shouldEdit;
  final bool isDraftView;
  final bool thumbnailOnly;

  const MakerItemTile({
    super.key,
    required this.doc,
    this.shouldEdit = false,
    this.isDraftView = false,
    this.thumbnailOnly = false,
  });

  bool _is5x8(Map<String, dynamic> data) {
    if (data['is5x8'] == true) return true;
    final w = data['width'] as num?;
    final h = data['height'] as num?;
    if (w != null && h != null) {
      final ratio = w / h;
      return ratio >= 0.58 && ratio <= 0.67;
    }
    return false;
  }

  Future<void> _confirmDelete(BuildContext context, String displayTitle) async {
    final isFanzine = doc.reference.path.startsWith('fanzines/');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete $displayTitle?"),
        content: Text(isFanzine ? "Are you sure?" : "Are you sure you want to delete this image?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (!context.mounted) return;
      if (isFanzine) {
        context.read<ProfileBloc>().add(DeleteFolioRequested(doc.id));
      } else {
        context.read<ProfileBloc>().add(DeleteImageRequested(doc.id));
      }
    }
  }

  Future<String?> _getFolioThumbnail(String fanzineId) async {
    final db = FirebaseFirestore.instance;
    try {
      final coverSnap = await db.collection('fanzines')
          .doc(fanzineId)
          .collection('pages')
          .where('pageNumber', isEqualTo: 1)
          .limit(1)
          .get();

      if (coverSnap.docs.isNotEmpty) {
        final d = coverSnap.docs.first.data();
        final url = d['gridUrl'] ?? d['thumbnailUrl'] ?? d['imageUrl'];
        if (url != null && url.toString().isNotEmpty) return url;
      }

      final pagesSnap = await db.collection('fanzines')
          .doc(fanzineId)
          .collection('pages')
          .where('pageNumber', isGreaterThan: 0)
          .orderBy('pageNumber')
          .limit(1)
          .get();

      if (pagesSnap.docs.isNotEmpty) {
        final pageData = pagesSnap.docs.first.data();
        final url = pageData['gridUrl'] ?? pageData['thumbnailUrl'] ?? pageData['imageUrl'];
        if (url != null && url.toString().isNotEmpty) return url;
      }
    } catch (e) {
      debugPrint("Error fetching folio thumbnail: $e");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final isFanzine = doc.reference.path.startsWith('fanzines/');
    final title = data['title'] ?? 'Untitled';
    String displayTitle = title;

    if (isFanzine) {
      final wNum = (data['wholeNumber'] ?? '').toString().trim();
      final iss = (data['issue'] ?? '').toString().trim();
      if (wNum.isNotEmpty) {
        displayTitle = "$title $wNum";
      } else if (iss.isNotEmpty) {
        displayTitle = "$title $iss";
      }
    }

    final fileUrl = data['fileUrl'];
    final displayUrl = data['gridUrl'] ?? data['fileUrl'];
    final Timestamp? publishedTs = data['publishedDate'] as Timestamp?;
    final int pageCount = data['pageCount'] ?? 0;
    final String datePrecision = data['datePrecision'] ?? 'month';

    return GestureDetector(
      onTap: () {
        if (!isFanzine) {
          showDialog(
            context: context,
            builder: (_) => ImageViewModal(
              imageUrl: fileUrl ?? '',
              imageId: doc.id,
              imageText: data['text'] ?? data['text_raw'],
            ),
          );
        } else {
          context.push(shouldEdit ? '/editor/${doc.id}' : '/reader/${doc.id}');
        }
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Colors.grey[200],
              child: isFanzine
                  ? FutureBuilder<String?>(
                future: _getFolioThumbnail(doc.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                  }
                  final thumbUrl = snapshot.data;
                  if (thumbUrl != null && thumbUrl.isNotEmpty) {
                    return Image.network(thumbUrl, fit: BoxFit.cover);
                  }
                  return const Icon(Icons.menu_book, color: Colors.black12, size: 40);
                },
              )
                  : (displayUrl != null
                  ? Image.network(displayUrl, fit: BoxFit.cover)
                  : const Icon(Icons.image, color: Colors.black12, size: 40)),
            ),
            if (!thumbnailOnly) ...[
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black54,
                  child: Text(
                    displayTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Positioned(
                top: 44,
                left: 4,
                right: 4,
                child: ProfileBadge(
                  label: isFanzine ? "folio • $pageCount pages" : (_is5x8(data) ? "full page 5x8" : "image"),
                  color: Colors.grey.shade800,
                ),
              ),
              if (isFanzine && publishedTs != null)
                Positioned(
                  top: 66,
                  left: 4,
                  right: 4,
                  child: ProfileBadge(
                    label: () {
                      final date = publishedTs.toDate();
                      if (datePrecision == 'day') return DateFormat('MMMM d, yyyy').format(date).toLowerCase();
                      if (datePrecision == 'year') return DateFormat('yyyy').format(date);
                      return DateFormat('MMMM yyyy').format(date).toLowerCase();
                    }(),
                    color: Colors.grey.shade800,
                  ),
                ),
            ],
            if (isDraftView && !thumbnailOnly)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => _confirmDelete(context, displayTitle),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}