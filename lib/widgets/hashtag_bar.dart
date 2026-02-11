import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/engagement_service.dart';

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
    if (currentUser == null) return; // Optional: Show login prompt
    await _service.toggleHashtag(widget.imageId, tag, !isSelected);
  }

  Future<void> _submitNewTag() async {
    if (_tagController.text.trim().isEmpty) {
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
      runSpacing: 4.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...tagItems.map((item) {
          final isApproved = item.name == 'approved';
          final color = isApproved
              ? (item.count > 0 ? Colors.green : Colors.grey)
              : (item.hasVoted ? Colors.blue : Colors.grey[700]);
          final bgColor = isApproved
              ? (item.count > 0 ? Colors.green.withValues(alpha: 0.1) : Colors.grey[200])
              : (item.hasVoted ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent);

          return GestureDetector(
            onTap: () => _handleVote(item.name, item.hasVoted),
            child: Chip(
              label: Text(
                "#${item.name} (${item.count})",
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: item.hasVoted ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              backgroundColor: bgColor,
              shape: StadiumBorder(side: BorderSide(color: color!.withOpacity(0.5))),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
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
            onTap: () => setState(() => _isAdding = true),
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