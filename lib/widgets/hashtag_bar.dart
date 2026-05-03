import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../services/engagement_service.dart';
import 'auth_modal.dart';

class HashtagBar extends StatefulWidget {
  final String imageId;
  final Map<String, dynamic> tags; // { "tag": [uid1, uid2] }

  const HashtagBar({
    super.key,
    required this.imageId,
    required this.tags,
  });

  @override
  State<HashtagBar> createState() => _HashtagBarState();
}

class _HashtagBarState extends State<HashtagBar> {
  final EngagementService _service = EngagementService();
  final TextEditingController _tagController = TextEditingController();
  bool _isAdding = false;

  User? get currentUser => FirebaseAuth.instance.currentUser;

  Future<void> _handleVote(String tag, bool isSelected) async {
    if (currentUser == null || currentUser!.isAnonymous) {
      showDialog(context: context, builder: (c) => const AuthModal());
      return;
    }
    await _service.toggleHashtag(widget.imageId, tag, !isSelected);
  }

  Future<void> _submitNewTag() async {
    if (_tagController.text.trim().isEmpty) {
      setState(() => _isAdding = false);
      return;
    }

    if (currentUser == null || currentUser!.isAnonymous) {
      showDialog(context: context, builder: (c) => const AuthModal());
      setState(() => _isAdding = false);
      return;
    }

    final newTag = _tagController.text.trim();
    await _service.toggleHashtag(widget.imageId, newTag, true);
    _tagController.clear();
    setState(() => _isAdding = false);
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Process tags into a list of objects for easier rendering
    final List<_TagItem> tagItems = [];
    widget.tags.forEach((key, value) {
      if (value is List) {
        tagItems.add(_TagItem(
          name: key,
          count: value.length,
          hasVoted: currentUser != null && value.contains(currentUser!.uid),
        ));
      }
    });

    // Sort: #approved first, then by count descending
    tagItems.sort((a, b) {
      if (a.name == 'approved') return -1;
      if (b.name == 'approved') return 1;
      return b.count.compareTo(a.count);
    });

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...tagItems.map((item) {
          final isApproved = item.name == 'approved';

          final color = isApproved
              ? (item.count > 0 ? Colors.green : Colors.grey)
              : (item.hasVoted ? Colors.blue : Colors.grey[700]);

          final bgColor = isApproved
              ? (item.count > 0 ? Colors.green.withValues(alpha: 0.1) : Colors.transparent)
              : (item.hasVoted ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent);

          // The New Split Button Layout
          return Container(
            decoration: BoxDecoration(
              // Outline dynamically deepens when voted
              border: Border.all(color: color!.withValues(alpha: item.hasVoted ? 1.0 : 0.5)),
              borderRadius: BorderRadius.circular(20),
              color: bgColor, // Transitions to tonal when voted
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // LEFT SIDE: Navigate to Profile -> Index Tab -> Hashtags SubTab
                InkWell(
                  onTap: () {
                    context.push('/${item.name}?tab=index&sub=hashtags');
                  },
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, right: 6, top: 4, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tag, size: 10, color: color), // Keeping hashtag icon here as requested
                        const SizedBox(width: 2),
                        Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: item.hasVoted ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // DIVIDER
                Container(
                  width: 1,
                  height: 14,
                  color: color.withValues(alpha: 0.3),
                ),

                // RIGHT SIDE: Vote Action (Now using Star/StarBorder)
                InkWell(
                  onTap: () => _handleVote(item.name, item.hasVoted),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6, right: 10, top: 4, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            item.hasVoted ? Icons.star : Icons.star_border,
                            size: 14,
                            color: color
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${item.count}",
                          style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        // Add Button
        if (_isAdding)
          SizedBox(
            width: 100,
            child: TextField(
              controller: _tagController,
              autofocus: true,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: "new tag",
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              ),
              onSubmitted: (_) => _submitNewTag(),
            ),
          )
        else
          GestureDetector(
            onTap: () {
              if (currentUser == null || currentUser!.isAnonymous) {
                showDialog(context: context, builder: (c) => const AuthModal());
                return;
              }
              setState(() => _isAdding = true);
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey),
              ),
              child: const Icon(Icons.add, size: 14, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}

class _TagItem {
  final String name;
  final int count;
  final bool hasVoted;

  _TagItem({required this.name, required this.count, required this.hasVoted});
}