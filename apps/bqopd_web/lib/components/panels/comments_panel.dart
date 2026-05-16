import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'dart:convert';
import '../../utils/web_firebase_interop.dart';
import '../../repositories/web_engagement_repository.dart';

class CommentsPanel extends StatefulComponent {
  final String imageId;

  const CommentsPanel({required this.imageId, super.key});

  @override
  State<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<CommentsPanel> {
  final WebEngagementRepository _repo = WebEngagementRepository();
  List<Map<String, dynamic>> _comments = [];
  String _newCommentText = "";
  bool _loading = true;
  dynamic _unsub;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    _unsub = fsListenQuery(
        'artifacts/bqopd/public/data/comments',
        'contentId', '==', jsonEncode(component.imageId),
        'createdAt', false,
            (jsonStr) {
          final List decoded = jsonDecode(jsonStr);
          setState(() {
            _comments = decoded.map((d) => d['data'] as Map<String, dynamic>).toList();
            _loading = false;
          });
        }
    );
  }

  @override
  void dispose() {
    if (_unsub != null) _unsub.callAsFunction();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_newCommentText.trim().isEmpty) return;

    final uid = getCurrentUserId();
    if (uid == null) return;

    await _repo.addComment(
      imageId: component.imageId,
      text: _newCommentText,
      // Metadata would be fetched from user profile in a full implementation
    );

    setState(() => _newCommentText = "");
  }

  @override
  Component build(BuildContext context) {
    if (_loading) return p([text('Loading thoughts...')]);

    return div(classes: 'flex-col', [
      if (_comments.isEmpty)
        p(classes: 'text-gray text-sm italic mb-4', [text('No thoughts shared yet.')])
      else
        for (var comment in _comments)
          div(classes: 'mb-4 pb-2', attributes: {'style': 'border-bottom: 1px solid #f0f0f0;'}, [
            div(classes: 'flex-row items-center gap-2 mb-1', [
              span(classes: 'font-bold text-xs', [text(comment['username'] ?? 'anonymous')]),
              span(classes: 'text-gray', attributes: {'style': 'font-size: 9px;'}, [text('just now')])
            ]),
            p(classes: 'text-sm', [text(comment['text'] ?? '')])
          ]),

      div(classes: 'flex-row gap-2 mt-2', [
        input(
          attributes: {
            'placeholder': 'Add a thought...',
            'value': _newCommentText,
            'style': 'flex: 1; margin-bottom: 0;'
          },
          events: {'input': (e) => _newCommentText = (e.target as dynamic).value},
        ),
        button(
            classes: 'nav-pill',
            events: {'click': (e) => _submit()},
            [text('Post')]
        )
      ])
    ]);
  }
}