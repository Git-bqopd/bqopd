import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/engagement_service.dart';
import '../comment_item.dart';

class CommentsPanel extends StatelessWidget {
  final String imageId;
  final EngagementService engagementService;
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isInline;

  const CommentsPanel({
    super.key,
    required this.imageId,
    required this.engagementService,
    required this.controller,
    required this.onSend,
    this.isInline = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isInline)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: _CommentList(imageId: imageId, service: engagementService),
          )
        else
          Expanded(
            child: _CommentList(imageId: imageId, service: engagementService),
          ),
        _CommentInput(controller: controller, onSend: onSend),
      ],
    );
  }
}

class _CommentList extends StatelessWidget {
  final String imageId;
  final EngagementService service;

  const _CommentList({required this.imageId, required this.service});

  @override
  Widget build(BuildContext context) {
    if (imageId.isEmpty) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: service.getCommentsStream(imageId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();

        final sortedDocs = snap.data!.docs.map((d) {
          final m = d.data() as Map<String, dynamic>;
          m['_id'] = d.id;
          return m;
        }).toList();

        sortedDocs.sort((a, b) {
          final aT = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          final bT = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          return aT.compareTo(bT);
        });

        if (sortedDocs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text("No comments yet."),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: sortedDocs.length,
          separatorBuilder: (c, i) => const Divider(height: 1, color: Colors.black12),
          itemBuilder: (c, i) => CommentItem(data: sortedDocs[i]),
        );
      },
    );
  }
}

class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _CommentInput({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "Add a comment...",
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: onSend)
        ],
      ),
    );
  }
}