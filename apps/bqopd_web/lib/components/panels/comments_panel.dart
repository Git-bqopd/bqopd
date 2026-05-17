import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';

class CommentsPanel extends StatefulComponent {
  final String imageId;

  const CommentsPanel({required this.imageId, super.key});

  @override
  State<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<CommentsPanel> {
  List<Map<String, dynamic>> _comments = [];
  String _newCommentText = "";
  bool _loading = true;
  dynamic _unsub;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void didUpdateComponent(CommentsPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _stopListening();
      _startListening();
    }
  }

  void _startListening() {
    if (component.imageId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    _unsub = fsListenQuery(
        'artifacts/bqopd/public/data/comments',
        'contentId', '==', jsonEncode(component.imageId),
        '',
        false,
            (jsonStr) {
          final List decoded = jsonDecode(jsonStr);
          final List<Map<String, dynamic>> list = decoded.map((d) {
            final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
            data['_id'] = d['id'];
            return data;
          }).toList();

          list.sort((a, b) {
            final DateTime? tA = a['createdAt'] as DateTime?;
            final DateTime? tB = b['createdAt'] as DateTime?;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tA.compareTo(tB);
          });

          if (mounted) {
            setState(() {
              _comments = list;
              _loading = false;
            });
          }
        }
    );
  }

  void _stopListening() {
    if (_unsub != null) {
      try {
        _unsub.callAsFunction();
        _unsub = null;
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _submit() async {
    final textVal = _newCommentText.trim();
    if (textVal.isEmpty) return;

    final uid = getCurrentUserId();
    if (uid == null) return;

    final uRes = await fsGetDoc('profiles/$uid');
    final uDoc = jsonDecode(uRes);
    String username = 'anonymous';
    String displayName = '';

    if (uDoc['exists'] == true) {
      username = uDoc['data']['username'] ?? 'anonymous';
      displayName = uDoc['data']['displayName'] ?? '';
    }

    await fsAddDoc('artifacts/bqopd/public/data/comments', jsonEncode({
      'contentId': component.imageId,
      'userId': uid,
      'text': textVal,
      'createdAt': WebFieldValue.serverTimestamp(),
      'likeCount': 0,
      'username': username,
      'displayName': displayName,
    }));

    await fsUpdateDoc('images/${component.imageId}', jsonEncode({
      'commentCount': WebFieldValue.increment(1)
    }));

    if (mounted) {
      setState(() => _newCommentText = "");
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) return div(classes: 'p-4 text-center', [text('Loading thoughts...')]);

    return div(classes: 'flex-col', [
      if (_comments.isEmpty)
        div(classes: 'p-8 text-center text-gray text-sm italic', [text('No thoughts shared yet.')])
      else
        for (var comment in _comments)
          CommentItem(data: comment, key: ValueKey(comment['_id'])),

      div(classes: 'flex-row gap-2 mt-4 p-2 bg-gray-50 rounded-lg items-center', [
        div(classes: 'flex-1', [
          input(
            classes: 'w-full p-2 border border-gray-200 rounded-md text-sm',
            attributes: {
              'placeholder': 'Add a thought...',
              'value': _newCommentText,
            },
            events: {'input': (e) => _newCommentText = (e.target as dynamic).value},
          ),
        ]),
        button(
            classes: 'nav-pill mb-0',
            events: {'click': (e) => _submit()},
            [
              span(classes: 'material-symbols-outlined text-sm', [text('send')])
            ]
        )
      ])
    ]);
  }
}

class CommentItem extends StatefulComponent {
  final Map<String, dynamic> data;
  const CommentItem({required this.data, super.key});

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  Map<String, dynamic>? _profile;
  bool _isLiked = false;
  dynamic _likeUnsub;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _listenToLikes();
  }

  @override
  void dispose() {
    if (_likeUnsub != null) {
      try { _likeUnsub.callAsFunction(); } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = component.data['userId'];
    if (uid == null) return;

    final res = await fsGetDoc('profiles/$uid');
    final doc = jsonDecode(res);
    if (doc['exists'] && mounted) {
      setState(() => _profile = doc['data']);
    }
  }

  void _listenToLikes() {
    final uid = getCurrentUserId();
    final commentId = component.data['_id'];
    if (uid == null || commentId == null) return;

    _likeUnsub = fsListenDoc('Users/$uid/activity/likes/comments/$commentId', (jsonStr) {
      final doc = jsonDecode(jsonStr);
      if (mounted) {
        setState(() => _isLiked = doc['exists'] == true);
      }
    });
  }

  Future<void> _handleLike() async {
    final uid = getCurrentUserId();
    final commentId = component.data['_id'];
    if (uid == null || commentId == null) return;

    final newStatus = !_isLiked;
    if (newStatus) {
      await fsUpdateDoc('artifacts/bqopd/public/data/comments/$commentId', jsonEncode({'likeCount': WebFieldValue.increment(1)}));
      await fsSetDoc('Users/$uid/activity/likes/comments/$commentId', jsonEncode({'likedAt': WebFieldValue.serverTimestamp()}), true);
    } else {
      await fsUpdateDoc('artifacts/bqopd/public/data/comments/$commentId', jsonEncode({'likeCount': WebFieldValue.increment(-1)}));
      await fsDeleteDoc('Users/$uid/activity/likes/comments/$commentId');
    }
  }

  @override
  Component build(BuildContext context) {
    final String displayName = _profile?['displayName'] ?? component.data['displayName'] ?? 'user';
    final String username = _profile?['username'] ?? component.data['username'] ?? 'anonymous';
    final String? photoUrl = _profile?['photoUrl'];
    final String textContent = component.data['text'] ?? '';
    final int likeCount = component.data['likeCount'] ?? 0;

    // Simple date format
    String dateStr = '';
    if (component.data['createdAt'] is DateTime) {
      final dt = component.data['createdAt'] as DateTime;
      dateStr = '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}.${dt.year.toString().substring(2)}';
    }

    return div(classes: 'flex-row gap-3 py-4 border-b border-gray-100 items-start', [
      // Avatar
      div(classes: 'w-10 h-10 rounded-full bg-gray-100 overflow-hidden flex-shrink-0 border border-gray-200', [
        if (photoUrl != null && photoUrl.isNotEmpty)
          img(src: photoUrl, classes: 'w-full h-full object-cover')
        else
          div(classes: 'w-full h-full flex items-center justify-center text-gray-400 font-bold text-xs', [
            text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')
          ])
      ]),

      // Content Area
      div(classes: 'flex-1 flex-col', [
        div(classes: 'flex-row justify-between items-start', [
          div(classes: 'flex-col', [
            div(classes: 'flex-row items-center gap-1', [
              span(classes: 'font-bold text-sm text-black', [text(displayName)]),
              span(classes: 'text-gray-500 text-xs', [text('@$username')]),
            ]),
            span(classes: 'text-gray-400 text-xs mt-0.5', [text(dateStr)]),
          ]),

          // Like Button
          button(
              classes: 'flex-row items-center gap-1 bg-transparent border-none cursor-pointer group p-1 rounded hover:bg-gray-50',
              events: {'click': (e) => _handleLike()},
              [
                span(classes: 'text-xs font-bold ${_isLiked ? 'text-red-500' : 'text-gray-400'}', [
                  text(likeCount > 0 ? '$likeCount' : '')
                ]),
                span(
                    classes: 'material-symbols-outlined text-sm ${_isLiked ? 'text-red-500' : 'text-gray-300 group-hover:text-gray-400'}',
                    attributes: {'style': _isLiked ? "font-variation-settings: 'FILL' 1;" : ""},
                    [text('favorite')]
                ),
              ]
          ),
        ]),

        p(classes: 'text-sm text-gray-800 mt-2 leading-relaxed', [text(textContent)]),
      ])
    ]);
  }
}