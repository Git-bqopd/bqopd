import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../blocs/interaction/interaction_bloc.dart';
import '../../services/user_provider.dart';
import '../comment_item.dart';
import '../auth_modal.dart';

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

  @override
  void initState() {
    super.initState();
    // Trigger the load event when the panel is mounted
    context.read<InteractionBloc>().add(LoadCommentsRequested(widget.imageId));
  }

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
    return BlocBuilder<InteractionBloc, InteractionState>(
      builder: (context, state) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.isLoadingComments)
              const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
            else
              _CommentList(comments: state.comments, imageId: widget.imageId),
            _CommentInput(controller: _controller, onSend: _onSend),
          ],
        );
      },
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No comments yet. Be the first to share a thought!"),
        ),
      );
    }

    // Sort locally by creation date
    final sorted = List<DocumentSnapshot>.from(comments);
    sorted.sort((a, b) {
      final aT = (a.data() as Map?)?['createdAt'] as Timestamp?;
      final bT = (b.data() as Map?)?['createdAt'] as Timestamp?;
      if (aT == null) return 1;
      if (bT == null) return -1;
      return aT.compareTo(bT);
    });

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length,
      separatorBuilder: (c, i) => const Divider(height: 1, color: Colors.black12),
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

    return Padding(
      padding: const EdgeInsets.only(top: 12),
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
              decoration: const InputDecoration(
                  hintText: "Add a thought...",
                  isDense: true,
                  border: OutlineInputBorder()
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.send),
              onPressed: onSend
          )
        ],
      ),
    );
  }
}