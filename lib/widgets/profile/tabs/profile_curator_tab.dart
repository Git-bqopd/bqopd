import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../components/profile_entity_row.dart';
import '../utils/profile_utils.dart';

class ProfileCuratorTab extends StatelessWidget {
  final int subTabIndex;
  final String targetUserId;
  final bool canEdit;

  const ProfileCuratorTab({
    super.key,
    required this.subTabIndex,
    required this.targetUserId,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (subTabIndex == 2) {
      return _buildEntitiesSubView(targetUserId);
    } else if (subTabIndex == 3) {
      return _buildAITrainingDataSubView(targetUserId);
    }
    return _buildCuratorSubView(targetUserId, canEdit);
  }

  Widget _buildCuratorSubView(String targetUserId, bool canEdit) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return SliverToBoxAdapter(child: Center(child: Text("Error: ${snap.error}", style: const TextStyle(color: Colors.grey))));
        if (!snap.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));

        final filtered = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
          final bool isTargetUserItem = (owner == targetUserId || (data['editors'] as List? ?? []).contains(targetUserId));

          if (!isTargetUserItem) return false;

          final hasSource = data.containsKey('sourceFile');
          final isLive = data['isLive'] ?? false;
          if (subTabIndex == 0) return hasSource && !isLive;
          return (!hasSource || isLive);
        }).toList();

        filtered.sort(canonicalFanzineSort);
        return buildProfileGrid(filtered, true, isDraftView: canEdit);
      },
    );
  }

  Widget _buildEntitiesSubView(String targetUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return SliverToBoxAdapter(child: Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.grey))));
        if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));

        final Map<String, int> entityCounts = {};
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final owner = data['ownerId'] ?? data['editorId'] ?? data['uploaderId'] ?? '';
          final bool isTargetUserItem = (owner == targetUserId || (data['editors'] as List? ?? []).contains(targetUserId));
          if (!isTargetUserItem) continue;

          final hasSource = data.containsKey('sourceFile');
          final isLive = data['isLive'] ?? false;
          if (!hasSource || isLive) continue;

          final entities = List<String>.from(data['draftEntities'] ?? []);
          for (var name in entities) {
            entityCounts[name] = (entityCounts[name] ?? 0) + 1;
          }
        }

        if (entityCounts.isEmpty) return const SliverToBoxAdapter(child: Center(child: Text("No entities found.")));
        final sortedNames = entityCounts.keys.toList()..sort((a, b) => entityCounts[b]!.compareTo(entityCounts[a]!));

        return SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                        (context, index) => ProfileEntityRow(name: sortedNames[index], count: entityCounts[sortedNames[index]]!),
                    childCount: sortedNames.length
                )
            )
        );
      },
    );
  }

  Widget _buildAITrainingDataSubView(String targetUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('images')
          .where('isTrainingData', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(child: Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.grey))));
        }
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }

        final docs = snapshot.data!.docs;
        final List<Map<String, dynamic>> trainingCandidates = [];

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final int correctionScore = data['human_correction_score'] ?? 0;
          final int linkingScore = data['human_linking_score'] ?? 0;

          if (correctionScore > 0 || linkingScore > 0) {
            String displayTitle = data['title'] ?? data['fileName'] ?? 'Untitled';
            final wNum = (data['wholeNumber'] ?? '').toString().trim();
            final iss = (data['issue'] ?? '').toString().trim();
            if (wNum.isNotEmpty) {
              displayTitle = "$displayTitle $wNum";
            } else if (iss.isNotEmpty) {
              displayTitle = "$displayTitle $iss";
            }
            trainingCandidates.add({
              'id': doc.id,
              'title': displayTitle,
              'correctionScore': correctionScore,
              'linkingScore': linkingScore,
              'fileUrl': data['fileUrl'] ?? data['gridUrl'],
              'folioContext': data['folioContext'],
            });
          }
        }

        if (trainingCandidates.isEmpty) {
          return const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Center(
                      child: Text(
                          "No training data yet.",
                          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                          textAlign: TextAlign.center
                      )
                  )
              )
          );
        }

        trainingCandidates.sort((a, b) {
          final scoreA = (a['correctionScore'] as int) + (a['linkingScore'] as int);
          final scoreB = (b['correctionScore'] as int) + (b['linkingScore'] as int);
          return scoreB.compareTo(scoreA);
        });

        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = trainingCandidates[index];
              final String? folioContext = item['folioContext'];

              Widget buildCard(String title) {
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                  child: ListTile(
                    leading: item['fileUrl'] != null ? Image.network(item['fileUrl'], width: 40, height: 40, fit: BoxFit.cover) : const Icon(Icons.image),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text("Correction Edits: ${item['correctionScore']} | Link Edits: ${item['linkingScore']}", style: const TextStyle(fontSize: 11)),
                  ),
                );
              }

              if (folioContext != null && folioContext.isNotEmpty) {
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('fanzines').doc(folioContext).get(),
                  builder: (context, fzSnap) {
                    String finalTitle = item['title'];
                    if (fzSnap.hasData && fzSnap.data!.exists) {
                      final fzData = fzSnap.data!.data() as Map<String, dynamic>;
                      final fzTitle = fzData['title'] ?? 'Untitled';
                      final wNum = (fzData['wholeNumber'] ?? '').toString().trim();
                      final iss = (fzData['issue'] ?? '').toString().trim();
                      if (wNum.isNotEmpty) finalTitle = "$fzTitle $wNum";
                      else if (iss.isNotEmpty) finalTitle = "$fzTitle $iss";
                      else finalTitle = fzTitle;
                    }
                    return buildCard(finalTitle);
                  },
                );
              }
              return buildCard(item['title']);
            }, childCount: trainingCandidates.length),
          ),
        );
      },
    );
  }
}