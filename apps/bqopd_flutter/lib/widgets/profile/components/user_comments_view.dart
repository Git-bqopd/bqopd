import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../comment_item.dart';

class UserCommentsView extends StatelessWidget {
  final String userId;

  const UserCommentsView({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('artifacts')
          .doc('bqopd')
          .collection('public')
          .doc('data')
          .collection('comments')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SliverToBoxAdapter(
            child: SizedBox(
              height: 100,
              child: Center(
                child: Text("No comments found.", style: TextStyle(color: Colors.grey)),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!.docs.toList();
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: SizedBox(
              height: 100,
              child: Center(
                child: Text("No comments found.", style: TextStyle(color: Colors.grey)),
              ),
            ),
          );
        }

        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['createdAt'] as Timestamp?;
          final bTime = bData['createdAt'] as Timestamp?;
          return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
        });

        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                data['_id'] = docs[index].id;

                return CommentItem(
                  key: ValueKey(docs[index].id),
                  data: data,
                  isProfileView: true,
                );
              },
              childCount: docs.length,
            ),
          ),
        );
      },
    );
  }
}