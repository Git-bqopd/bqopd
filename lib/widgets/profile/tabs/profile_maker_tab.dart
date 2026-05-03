import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../components/moderator_card.dart';
import '../utils/profile_utils.dart';

class ProfileMakerTab extends StatelessWidget {
  final int subTabIndex;
  final String targetUserId;
  final bool canSeeDrafts;

  const ProfileMakerTab({
    super.key,
    required this.subTabIndex,
    required this.targetUserId,
    required this.canSeeDrafts,
  });

  @override
  Widget build(BuildContext context) {
    if (subTabIndex == 2) {
      return _buildModeratorSubView();
    }
    return _buildMakerCombinedView(targetUserId: targetUserId, showDrafts: subTabIndex == 1 && canSeeDrafts);
  }

  Widget _buildModeratorSubView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('images')
          .where('status', isEqualTo: 'pending')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(child: Center(child: SelectableText("Error: ${snapshot.error}")));
        }
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Queue clear. Good job!"))));
        }

        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: ModeratorCard(docId: docs[index].id, data: data),
                );
              },
              childCount: docs.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMakerCombinedView({required String targetUserId, required bool showDrafts}) {
    return FutureBuilder<List<dynamic>>(
        future: _getCombinedData(targetUserId, showDrafts),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
          final items = snapshot.data!;
          if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No items found"))));

          return buildProfileGrid(items, true, isDraftView: showDrafts);
        }
    );
  }

  Future<List<dynamic>> _getCombinedData(String targetUserId, bool showDrafts) async {
    final fzSnap = await FirebaseFirestore.instance.collection('fanzines').get();
    final imgSnap = await FirebaseFirestore.instance.collection('images').get();
    final List<dynamic> combined = [];

    for (var doc in fzSnap.docs) {
      final data = doc.data();
      if (data['type'] != 'folio' && data['type'] != 'calendar' && data['type'] != 'article') continue;
      if (data['processingStatus'] == 'draft_calendar') continue;

      final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
      if (owner != targetUserId) continue;

      final isLive = data['isLive'] ?? false;
      if (showDrafts ? !isLive : isLive) combined.add(doc);
    }

    for (var doc in imgSnap.docs) {
      final data = doc.data();
      if (data['uploaderId'] != targetUserId) continue;

      final isPending = data['status'] == 'pending';
      if (showDrafts ? isPending : !isPending) combined.add(doc);
    }

    combined.sort((a, b) => canonicalFanzineSort(a as DocumentSnapshot, b as DocumentSnapshot));
    return combined;
  }
}