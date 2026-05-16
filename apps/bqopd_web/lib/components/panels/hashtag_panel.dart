import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';

/// A Jaspr implementation of the Hashtag voting system.
/// Uses the CSS-defined .m3-chip and .m3-split-button classes for an identical look to Flutter.
class HashtagPanel extends StatefulComponent {
  final String imageId;

  const HashtagPanel({required this.imageId, super.key});

  @override
  State<HashtagPanel> createState() => _HashtagPanelState();
}

class _HashtagPanelState extends State<HashtagPanel> {
  Map<String, dynamic> _tags = {};
  bool _isAdding = false;
  String _newTagText = "";
  dynamic _unsub;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    if (component.imageId.isEmpty) return;
    _unsub = fsListenDoc('images/${component.imageId}', (jsonStr) {
      final doc = jsonDecode(jsonStr);
      if (doc['exists'] && mounted) {
        setState(() {
          _tags = doc['data']['tags'] as Map<String, dynamic>? ?? {};
        });
      }
    });
  }

  void _stopListening() {
    if (_unsub != null) {
      try { _unsub.callAsFunction(); } catch (_) {}
      _unsub = null;
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _toggleVote(String tag, bool isSelected) async {
    final uid = getCurrentUserId();
    if (uid == null) return;
    final cleanTag = tag.toLowerCase().replaceAll('#', '').trim();
    if (isSelected) {
      await fsUpdateDoc('images/${component.imageId}', jsonEncode({'tags.$cleanTag': WebFieldValue.arrayRemove([uid])}));
    } else {
      await fsUpdateDoc('images/${component.imageId}', jsonEncode({'tags.$cleanTag': WebFieldValue.arrayUnion([uid])}));
    }
  }

  Future<void> _submitNewTag() async {
    final text = _newTagText.trim().toLowerCase().replaceAll('#', '');
    if (text.isEmpty) { setState(() => _isAdding = false); return; }
    final uid = getCurrentUserId();
    if (uid == null) return;
    await fsUpdateDoc('images/${component.imageId}', jsonEncode({'tags.$text': WebFieldValue.arrayUnion([uid])}));
    setState(() { _newTagText = ""; _isAdding = false; });
  }

  @override
  Component build(BuildContext context) {
    final uid = getCurrentUserId();
    final List<_TagData> tagList = [];
    _tags.forEach((key, value) {
      if (value is List) {
        tagList.add(_TagData(
            name: key,
            count: value.length,
            hasVoted: uid != null && value.contains(uid)
        ));
      }
    });

    // Sort: approved first, then by count
    tagList.sort((a, b) => a.name == 'approved' ? -1 : (b.name == 'approved' ? 1 : b.count.compareTo(a.count)));

    return div(classes: 'flex-row flex-wrap gap-3 items-center py-4', [
      for (var tag in tagList) _buildTagChip(tag),

      if (_isAdding)
        _buildSplitButton()
      else
        button(
            classes: 'm3-chip hover:bg-gray-100',
            events: {'click': (e) => setState(() => _isAdding = true)},
            [
              span(classes: 'material-symbols-outlined chip-icon', [text('add')]),
            ]
        )
    ]);
  }

  Component _buildTagChip(_TagData tag) {
    return div(
        classes: 'm3-chip ${tag.hasVoted ? 'active' : ''}',
        events: {'click': (e) => _toggleVote(tag.name, tag.hasVoted)},
        [
          text('#${tag.name}'),
          div(classes: 'v-divider', []),
          span(
              classes: 'material-symbols-outlined chip-icon',
              // Match Material 3 symbol styling: FILL 1 when active
              attributes: {'style': tag.hasVoted ? "font-variation-settings: 'FILL' 1;" : "font-variation-settings: 'FILL' 0;"},
              [text(tag.hasVoted ? 'star' : 'star_outline')]
          ),
          text('${tag.count}'),
        ]
    );
  }

  Component _buildSplitButton() {
    return div(classes: 'm3-split-button', [
      input(
        attributes: {
          'placeholder': 'new tag...',
          'value': _newTagText,
          'autofocus': 'true'
        },
        events: {
          'input': (e) => _newTagText = (e.target as dynamic).value,
          'keypress': (e) { if ((e as dynamic).key == 'Enter') _submitNewTag(); }
        },
      ),
      div(classes: 'v-divider', []),
      div(
          classes: 'split-action',
          events: {'click': (e) => _submitNewTag()},
          [span(classes: 'material-symbols-outlined text-green-600', [text('check')])]
      ),
      div(classes: 'v-divider', []),
      div(
          classes: 'split-action',
          events: {'click': (e) => setState(() => _isAdding = false)},
          [span(classes: 'material-symbols-outlined text-gray-400', [text('close')])]
      ),
    ]);
  }
}

class _TagData {
  final String name;
  final int count;
  final bool hasVoted;
  _TagData({required this.name, required this.count, required this.hasVoted});
}