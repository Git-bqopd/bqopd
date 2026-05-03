import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/engagement_service.dart';
import 'auth_modal.dart';

/// Displays a comment with a clean, archival aesthetic.
class CommentItem extends StatelessWidget {
  final Map<String, dynamic> data;

  const CommentItem({
    super.key,
    required this.data,
  });

  Future<void> _handleDelete(BuildContext context, EngagementService service, String commentId, String imageId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text("REMOVE THOUGHT?", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.2)),
        content: const Text("This action cannot be undone.", style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL", style: TextStyle(color: Colors.black, fontSize: 12))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("DELETE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await service.deleteComment(commentId, imageId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String commentId = data['_id'] ?? '';
    final String userId = data['userId'] ?? '';
    final String imageId = data['contentId'] ?? '';
    final String text = data['text'] ?? '';
    final int likeCount = data['likeCount'] ?? 0;

    final String fallbackUsername = data['username'] ?? 'user';
    final String fallbackDisplayName = data['displayName'] ?? '';

    final contextData = data['context'] as Map?;
    final String fzTitle = contextData?['fanzineTitle'] ?? '';

    String timeAgo = '';
    if (data['createdAt'] != null) {
      final DateTime date = (data['createdAt'] as Timestamp).toDate();
      timeAgo = DateFormat('MM.dd.yy').format(date);
    }

    final EngagementService service = EngagementService();
    final user = FirebaseAuth.instance.currentUser;
    final bool isGuest = user == null || user.isAnonymous;
    final bool isOwner = !isGuest && user.uid == userId;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('profiles').doc(userId).get(),
      builder: (context, profileSnap) {
        String display = fallbackDisplayName;
        String handle = fallbackUsername;
        String? photoUrl;

        if (profileSnap.hasData && profileSnap.data!.exists) {
          final profileData = profileSnap.data!.data() as Map<String, dynamic>;
          display = profileData['displayName'] ?? '';
          handle = profileData['username'] ?? fallbackUsername;
          photoUrl = profileData['photoUrl'];
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Identity & Timestamp
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.push('/$handle'),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                        image: photoUrl != null && photoUrl.isNotEmpty
                            ? DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover)
                            : null,
                      ),
                      child: (photoUrl == null || photoUrl.isEmpty)
                          ? Center(
                        child: Text(
                          (display.isNotEmpty ? display[0] : handle[0]).toUpperCase(),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
                        ),
                      )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              (display.isNotEmpty ? display : handle).toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              timeAgo,
                              style: TextStyle(color: Colors.grey[400], fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Text(
                          "@$handle",
                          style: TextStyle(color: Colors.grey[500], fontSize: 10),
                        ),
                      ],
                    ),
                  ),

                  // Interaction Buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StreamBuilder<bool>(
                        stream: service.isCommentLikedStream(commentId),
                        builder: (context, snapshot) {
                          final bool isLiked = snapshot.data ?? false;
                          return GestureDetector(
                            onTap: () {
                              if (isGuest) {
                                showDialog(context: context, builder: (c) => const AuthModal());
                              } else {
                                service.toggleCommentLike(commentId, isLiked);
                              }
                            },
                            child: Row(
                              children: [
                                if (likeCount > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4.0),
                                    child: Text("$likeCount", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLiked ? Colors.redAccent : Colors.grey[400])),
                                  ),
                                Icon(
                                  isLiked ? Icons.favorite : Icons.favorite_border,
                                  size: 14,
                                  color: isLiked ? Colors.redAccent : Colors.grey[300],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (isOwner)
                        Padding(
                          padding: const EdgeInsets.only(left: 12.0),
                          child: GestureDetector(
                            onTap: () => _handleDelete(context, service, commentId, imageId),
                            child: Icon(Icons.delete_outline, size: 14, color: Colors.grey[300]),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // The Thought Body
              Padding(
                padding: const EdgeInsets.only(left: 38.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.black87,
                        fontFamily: 'Georgia',
                      ),
                    ),
                    if (fzTitle.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          "via $fzTitle",
                          style: TextStyle(fontSize: 9, color: Colors.grey[500], fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}