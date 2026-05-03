import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/engagement_service.dart';
import 'auth_modal.dart';

/// Displays a comment within a modern card.
/// Features a split-button identity layout and dynamic thumbnails.
class CommentItem extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isProfileView; // Controls dual-thumbnail display

  const CommentItem({
    super.key,
    required this.data,
    this.isProfileView = false,
  });

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  late Future<DocumentSnapshot> _profileFuture;
  late Future<Map<String, String?>> _thumbnailsFuture;

  @override
  void initState() {
    super.initState();
    _initFutures();
  }

  @override
  void didUpdateWidget(covariant CommentItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data['_id'] != widget.data['_id']) {
      _initFutures();
    }
  }

  void _initFutures() {
    final String userId = widget.data['userId'] ?? '';
    final String imageId = widget.data['contentId'] ?? '';
    final contextData = widget.data['context'] as Map?;
    final String? fzId = contextData?['fanzineId'];

    _profileFuture = FirebaseFirestore.instance.collection('profiles').doc(userId).get();
    _thumbnailsFuture = _getThumbnails(fzId, imageId);
  }

  Future<void> _handleDelete(BuildContext context, EngagementService service, String commentId, String imageId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("REMOVE COMMENT?", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.2)),
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

  /// Fetches both the fanzine cover AND the specific image thumbnail.
  Future<Map<String, String?>> _getThumbnails(String? fanzineId, String imageId) async {
    final db = FirebaseFirestore.instance;
    String? coverUrl;
    String? imageUrl;

    // 1. Get specific image thumbnail
    if (imageId.isNotEmpty) {
      try {
        final imgDoc = await db.collection('images').doc(imageId).get();
        if (imgDoc.exists) {
          final d = imgDoc.data() as Map<String, dynamic>;
          imageUrl = d['gridUrl'] ?? d['fileUrl'];
        }
      } catch (e) {
        debugPrint("Image thumbnail fetch error: $e");
      }
    }

    // 2. Get fanzine cover thumbnail
    if (fanzineId != null && fanzineId.isNotEmpty) {
      try {
        // Try page 1 first
        final snap = await db.collection('fanzines').doc(fanzineId).collection('pages')
            .where('pageNumber', isEqualTo: 1).limit(1).get();

        if (snap.docs.isNotEmpty) {
          final d = snap.docs.first.data();
          coverUrl = d['gridUrl'] ?? d['thumbnailUrl'] ?? d['imageUrl'];
        } else {
          // Fallback to the first ordered page
          final snap2 = await db.collection('fanzines').doc(fanzineId).collection('pages')
              .where('pageNumber', isGreaterThan: 0)
              .orderBy('pageNumber').limit(1).get();

          if (snap2.docs.isNotEmpty) {
            final d = snap2.docs.first.data();
            coverUrl = d['gridUrl'] ?? d['thumbnailUrl'] ?? d['imageUrl'];
          }
        }
      } catch (e) {
        debugPrint("Cover thumbnail fetch error: $e");
      }
    }

    return {'cover': coverUrl, 'image': imageUrl};
  }

  Widget _buildSingleThumb(String url, String? fzId) {
    return GestureDetector(
      onTap: () {
        if (fzId != null && fzId.isNotEmpty) {
          context.push('/reader/$fzId');
        }
      },
      child: Container(
        width: 50,
        constraints: const BoxConstraints(minHeight: 80, maxHeight: 120),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.network(url, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String? fzId) {
    return GestureDetector(
      onTap: () {
        if (fzId != null && fzId.isNotEmpty) {
          context.push('/reader/$fzId');
        }
      },
      child: Container(
        width: 50,
        constraints: const BoxConstraints(minHeight: 80, maxHeight: 120),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black12),
        ),
        child: const Center(child: Icon(Icons.menu_book, color: Colors.grey, size: 20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String commentId = widget.data['_id'] ?? '';
    final String userId = widget.data['userId'] ?? '';
    final String imageId = widget.data['contentId'] ?? '';
    final String text = widget.data['text'] ?? '';
    final int likeCount = widget.data['likeCount'] ?? 0;

    final String fallbackUsername = widget.data['username'] ?? 'user';
    final String fallbackDisplayName = widget.data['displayName'] ?? '';

    final contextData = widget.data['context'] as Map?;
    final String? fzId = contextData?['fanzineId'];

    String timeAgo = '';
    if (widget.data['createdAt'] != null) {
      final DateTime date = (widget.data['createdAt'] as Timestamp).toDate();
      timeAgo = DateFormat('MM.dd.yy').format(date);
    }

    final EngagementService service = EngagementService();
    final user = FirebaseAuth.instance.currentUser;
    final bool isGuest = user == null || user.isAnonymous;
    final bool isOwner = !isGuest && user.uid == userId;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withOpacity(0.05)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Thumbnails
            FutureBuilder<Map<String, String?>>(
                future: _thumbnailsFuture,
                builder: (context, snapshot) {
                  final thumbs = snapshot.data ?? {};
                  final coverUrl = thumbs['cover'];
                  final imageUrl = thumbs['image'];

                  List<Widget> images = [];

                  if (widget.isProfileView) {
                    // Profile View: Show both Cover AND Image if available and distinct
                    if (coverUrl != null) images.add(_buildSingleThumb(coverUrl, fzId));
                    if (imageUrl != null && imageUrl != coverUrl) {
                      if (images.isNotEmpty) images.add(const SizedBox(width: 4));
                      images.add(_buildSingleThumb(imageUrl, fzId));
                    }
                  } else {
                    // Reader View: Prefer Cover > Image (since they are already in the context)
                    final singleUrl = coverUrl ?? imageUrl;
                    if (singleUrl != null) {
                      images.add(_buildSingleThumb(singleUrl, fzId));
                    }
                  }

                  if (images.isEmpty) {
                    images.add(_buildPlaceholder(fzId));
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: images,
                    ),
                  );
                }
            ),

            // Right Column: Identity, Actions, and Content
            Expanded(
              child: FutureBuilder<DocumentSnapshot>(
                future: _profileFuture,
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

                  final String finalDisplayName = display.isNotEmpty ? display : handle;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row: Avatar, Identity, and Actions (Aligned Top)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Split Button Identity
                          Flexible(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    side: BorderSide(color: Colors.black.withOpacity(0.08)),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () => context.push('/$handle'),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 3, top: 3, bottom: 3, right: 12),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 15,
                                            backgroundColor: Colors.grey[100],
                                            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                                ? NetworkImage(photoUrl)
                                                : null,
                                            child: (photoUrl == null || photoUrl.isEmpty)
                                                ? Text(
                                              finalDisplayName.isNotEmpty ? finalDisplayName[0].toUpperCase() : '?',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                                            )
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 1,
                                            height: 22,
                                            color: Colors.black.withOpacity(0.08),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  finalDisplayName,
                                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.2, height: 1.1),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  "@$handle",
                                                  style: TextStyle(color: Colors.grey[500], fontSize: 10, height: 1.1),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    timeAgo,
                                    style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Spacer(),

                          // Interaction Buttons (Like/Delete) aligned to absolute top right
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      child: Row(
                                        children: [
                                          if (likeCount > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 4.0),
                                              child: Text("$likeCount", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isLiked ? Colors.redAccent : Colors.grey[500])),
                                            ),
                                          Icon(
                                            isLiked ? Icons.favorite : Icons.favorite_border,
                                            size: 16,
                                            color: isLiked ? Colors.redAccent : Colors.grey[400],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (isOwner)
                                GestureDetector(
                                  onTap: () => _handleDelete(context, service, commentId, imageId),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4.0, right: 4.0, top: 4.0),
                                    child: Icon(Icons.delete_outline, size: 16, color: Colors.grey[400]),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Comment Content
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}