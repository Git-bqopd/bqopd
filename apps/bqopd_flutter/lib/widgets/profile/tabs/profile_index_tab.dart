import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/profile_tabs_delegate.dart';
import '../components/profile_helpers.dart';
import '../components/user_comments_view.dart';
import '../utils/profile_utils.dart';
import 'package:bqopd_models/bqopd_models.dart';

class ProfileIndexTab extends StatelessWidget {
  final int subTabIndex;
  final UserProfile userData;
  final String profileName;

  const ProfileIndexTab({
    super.key,
    required this.subTabIndex,
    required this.userData,
    required this.profileName,
  });

  @override
  Widget build(BuildContext context) {
    if (subTabIndex == 0) {
      return SliverMainAxisGroup(slivers: _buildTagsSubView());
    } else if (subTabIndex == 1) {
      return _buildMentionsSubView();
    } else if (subTabIndex == 2) {
      return UserCommentsView(userId: userData.uid);
    }
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  List<Widget> _buildTagsSubView() {
    final cleanUsername = userData.username.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    final cleanDisplay = userData.displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');

    final Set<String> targetTags = {cleanUsername};
    if (cleanDisplay.isNotEmpty) targetTags.add(cleanDisplay);

    return [
      SliverPersistentHeader(
        pinned: true,
        delegate: ProfileTabsDelegate(
          child: Container(
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.black12)),
            ),
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: targetTags.map((t) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ProfileBadge(label: '#$t', color: Colors.black87),
                  )).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('images')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SliverToBoxAdapter(child: Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.grey))));
          }
          if (!snapshot.hasData) {
            return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
          }

          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final tags = data['tags'] as Map<String, dynamic>? ?? {};
            return targetTags.any((t) => tags.containsKey(t));
          }).toList();

          if (docs.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No items tagged yet.", style: TextStyle(color: Colors.grey)))));
          }

          return SliverPadding(
            padding: const EdgeInsets.all(8.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 5 / 8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8
              ),
              delegate: SliverChildBuilderDelegate(
                      (context, index) => ProfileHashtagItemTile(imageDoc: docs[index]),
                  childCount: docs.length
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildMentionsSubView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fanzines')
          .where('draftEntities', arrayContains: profileName)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Error loading mentions: ${snapshot.error}", style: const TextStyle(fontSize: 10, color: Colors.grey)))));
        }
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }

        final docs = snapshot.data!.docs.toList();
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No mentions found.", style: TextStyle(color: Colors.grey)))));
        }

        docs.sort(canonicalFanzineSort);
        return buildProfileGrid(docs, false, thumbnailOnly: true);
      },
    );
  }
}