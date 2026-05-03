import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'maker_item_tile.dart';

class ProfileBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ProfileBadge({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class ProfileQuickActionTile extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ProfileQuickActionTile({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: color,
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileHashtagItemTile extends StatelessWidget {
  final DocumentSnapshot imageDoc;

  const ProfileHashtagItemTile({
    super.key,
    required this.imageDoc,
  });

  @override
  Widget build(BuildContext context) {
    final data = imageDoc.data() as Map<String, dynamic>;
    final String? folioContext = data['folioContext'] ??
        (data['usedInFanzines'] != null && data['usedInFanzines'].isNotEmpty
            ? data['usedInFanzines'][0]
            : null);

    if (folioContext != null && folioContext.isNotEmpty) {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('fanzines').doc(folioContext).get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snap.hasData && snap.data != null && snap.data!.exists) {
            return MakerItemTile(doc: snap.data!, shouldEdit: false);
          }
          return MakerItemTile(doc: imageDoc, shouldEdit: false);
        },
      );
    }
    return MakerItemTile(doc: imageDoc, shouldEdit: false);
  }
}