import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../components/maker_item_tile.dart';

/// Standardized sorting logic for Fanzines across all profile tabs
int canonicalFanzineSort(DocumentSnapshot a, DocumentSnapshot b) {
  final aData = a.data() as Map<String, dynamic>;
  final bData = b.data() as Map<String, dynamic>;
  final Timestamp? aPubTs = aData['publishedDate'] as Timestamp?;
  final Timestamp? bPubTs = bData['publishedDate'] as Timestamp?;

  if (aPubTs != null && bPubTs == null) return -1;
  if (aPubTs == null && bPubTs != null) return 1;
  if (aPubTs != null && bPubTs != null) return bPubTs.compareTo(aPubTs);

  final String aTitle = (aData['title'] ?? '').toString().toLowerCase();
  final String bTitle = (bData['title'] ?? '').toString().toLowerCase();
  if (aTitle != bTitle) return bTitle.compareTo(aTitle);

  final int aVal = int.tryParse((aData['wholeNumber'] ?? aData['issue'] ?? '0').toString()) ?? 0;
  final int bVal = int.tryParse((bData['wholeNumber'] ?? bData['issue'] ?? '0').toString()) ?? 0;
  return bVal.compareTo(aVal);
}

/// Standardized sliver grid rendering used by multiple profile tabs
Widget buildProfileGrid(List<dynamic> docs, bool edit, {bool isDraftView = false, bool thumbnailOnly = false}) {
  return SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 8.0),
    sliver: SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 5 / 8,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8
      ),
      delegate: SliverChildBuilderDelegate(
            (context, index) => MakerItemTile(
            doc: docs[index],
            shouldEdit: edit,
            isDraftView: isDraftView,
            thumbnailOnly: thumbnailOnly
        ),
        childCount: docs.length,
      ),
    ),
  );
}