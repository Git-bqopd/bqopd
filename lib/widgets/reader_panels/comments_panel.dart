import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../blocs/interaction/interaction_bloc.dart';
import '../../services/user_provider.dart';
import '../../services/engagement_service.dart';
import '../comment_item.dart';
import '../auth_modal.dart';

/// A panel for reading and adding thoughts (comments) to a page.
/// Refactored to use a direct Stream for the list to prevent race conditions in ListViews.
class CommentsPanel extends StatefulWidget {
  final String imageId;
  final String? fanzineId;
  final String? fanzineTitle;
  final bool isInline;

  const CommentsPanel({
    super.key,
    required this.imageId,
    this.fanzineId,
    this.fanzineTitle,
    this.isInline = true,
  });

  @override
  State<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<CommentsPanel> {
  final TextEditingController _controller = TextEditingController();
  final EngagementService _engagementService = EngagementService();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSend() {
    if (_controller.text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      showDialog(context: context, builder: (c) => const AuthModal());
      return;
    }

    final userProvider = context.read<UserProvider>();

    context.read<InteractionBloc>().add(AddCommentRequested(
      imageId: widget.imageId,
      text: _controller.text.trim(),
      fanzineId: widget.fanzineId,
      fanzineTitle: widget.fanzineTitle,
      displayName: userProvider.userProfile?.displayName,
      username: userProvider.userProfile?.username,
    ));

    _controller.clear();
    if (widget.isInline) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageId.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Text(
          "Page registration pending. Comments will be available shortly.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "THOUGHTS",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: 2.0,
              ),
            ),
            StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('images').doc(widget.imageId).snapshots(),
                builder: (context, snapshot) {
                  final count = (snapshot.data?.data() as Map?)?['commentCount'] ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Text(
                    "$count",
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                  );
                }
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Refactored to direct stream to avoid singleton Bloc state fighting in lists
        StreamBuilder<QuerySnapshot>(
          stream: _engagementService.getCommentsStream(widget.imageId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)));
            }

            final docs = snapshot.data?.docs ?? [];
            return _CommentList(comments: docs, imageId: widget.imageId);
          },
        ),

        _CommentInput(controller: _controller, onSend: _onSend),
      ],
    );
  }
}

class _CommentList extends StatelessWidget {
  final List<DocumentSnapshot> comments;
  final String imageId;

  const _CommentList({required this.comments, required this.imageId});

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Icon(Icons.chat_bubble_outline, size: 24, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            const Text(
              "the margins are empty.\nwrite something.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.5, fontFamily: 'Georgia', fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    final sorted = List<DocumentSnapshot>.from(comments);
    sorted.sort((a, b) {
      final aT = (a.data() as Map?)?['createdAt'] as Timestamp?;
      final bT = (b.data() as Map?)?['createdAt'] as Timestamp?;
      if (aT == null) return 1;
      if (bT == null) return -1;
      return aT.compareTo(bT); // Ascending order for conversation flow
    });

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length,
      itemBuilder: (c, i) {
        final data = sorted[i].data() as Map<String, dynamic>;
        data['_id'] = sorted[i].id;
        return CommentItem(data: data);
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
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: isGuest,
              onTap: () {
                if (isGuest) {
                  showDialog(context: context, builder: (c) => const AuthModal());
                }
              },
              style: const TextStyle(fontSize: 14, fontFamily: 'Georgia'),
              maxLines: null,
              decoration: const InputDecoration(
                hintText: "Append a thought...",
                hintStyle: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 16),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.north_east_rounded, color: Colors.black, size: 20),
            onPressed: onSend,
          )
        ],
      ),
    );
  }
}