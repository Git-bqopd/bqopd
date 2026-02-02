import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/engagement_service.dart';

/// A standardized widget for displaying a single comment.
/// Fetches live user data from the Users collection based on the userId.
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
        title: const Text("Delete Comment?"),
        content: const Text("Are you sure you want to remove this thought?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Delete", style: TextStyle(color: Colors.red))
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
    final String imageId = data['contentId'] ?? ''; // Tied to global contentId
    final String text = data['text'] ?? '';
    final int likeCount = data['likeCount'] ?? 0;

    final String fallbackUsername = data['username'] ?? 'user';
    final String fallbackDisplayName = data['displayName'] ?? '';

    final contextData = data['context'] as Map?;
    final String fzTitle = contextData?['fanzineTitle'] ?? '';

    String timeAgo = '';
    if (data['createdAt'] != null) {
      final DateTime date = (data['createdAt'] as Timestamp).toDate();
      timeAgo = DateFormat.yMMMd().format(date);
    }

    final EngagementService service = EngagementService();
    final String? currentUid = FirebaseAuth.instance.currentUser?.uid;
    final bool isOwner = currentUid != null && currentUid == userId;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('Users').doc(userId).get(),
      builder: (context, userSnap) {
        String display = fallbackDisplayName;
        String handle = fallbackUsername;
        String? photoUrl;

        if (userSnap.hasData && userSnap.data!.exists) {
          final userData = userSnap.data!.data() as Map<String, dynamic>;
          display = userData['displayName'] ?? '';
          handle = userData['username'] ?? fallbackUsername;
          photoUrl = userData['photoUrl'];
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => context.push('/$handle'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? Text(
                      (display.isNotEmpty ? display[0] : handle[0]).toUpperCase(),
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => context.push('/$handle'),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (display.isNotEmpty)
                                  Text(
                                    display,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                if (display.isNotEmpty) const SizedBox(width: 4),
                                Text(
                                  "@$handle",
                                  style: TextStyle(
                                    color: display.isNotEmpty ? Colors.grey[600] : Colors.black,
                                    fontWeight: display.isNotEmpty ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeAgo,
                          style: TextStyle(color: Colors.grey[400], fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(text, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87)),
                    if (fzTitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        "via $fzTitle",
                        style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),

              // Action Area: Delete (if owner) and Like
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOwner)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: GestureDetector(
                        onTap: () => _handleDelete(context, service, commentId, imageId),
                        child: Icon(Icons.delete_outline, size: 16, color: Colors.grey[400]),
                      ),
                    ),
                  StreamBuilder<bool>(
                    stream: service.isCommentLikedStream(commentId),
                    builder: (context, snapshot) {
                      final bool isLiked = snapshot.data ?? false;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => service.toggleCommentLike(commentId, isLiked),
                            child: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 16,
                              color: isLiked ? Colors.red[300] : Colors.grey[300],
                            ),
                          ),
                          if (likeCount > 0)
                            Text("$likeCount", style: TextStyle(fontSize: 9, color: Colors.grey[400])),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}