import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';

class SocialToolbar extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final bool isGame;
  final String? youtubeId;
  final VoidCallback? onOpenGrid;

  // NEW: Panel State callbacks
  final BonusRowType? activeBonusRow;
  final ValueChanged<BonusRowType> onToggleBonusRow;

  const SocialToolbar({
    required this.imageId,
    this.fanzineId,
    this.isGame = false,
    this.youtubeId,
    this.onOpenGrid,
    required this.activeBonusRow,
    required this.onToggleBonusRow,
    super.key,
  });

  @override
  State<SocialToolbar> createState() => _SocialToolbarState();
}

class _SocialToolbarState extends State<SocialToolbar> {
  int _likeCount = 0;
  int _commentCount = 0;
  int _viewCount = 0;
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    if (component.imageId.isEmpty) return;
    final res = await fsGetDoc('images/${component.imageId}');
    final doc = jsonDecode(res);
    if (doc['exists']) {
      final data = doc['data'];
      setState(() {
        _likeCount = data['likeCount'] ?? 0;
        _commentCount = data['commentCount'] ?? 0;
        _viewCount = (data['regListCount'] ?? 0) + (data['anonListCount'] ?? 0) +
            (data['regGridCount'] ?? 0) + (data['anonGridCount'] ?? 0);
      });
    }

    final uid = getCurrentUserId();
    if (uid != null) {
      final likeRes = await fsGetDoc('Users/$uid/activity/likes/images/${component.imageId}');
      final likeDoc = jsonDecode(likeRes);
      setState(() => _isLiked = likeDoc['exists'] == true);
    }
  }

  Future<void> _handleLike() async {
    final uid = getCurrentUserId();
    if (uid == null) return;

    final newStatus = !_isLiked;
    setState(() {
      _isLiked = newStatus;
      _likeCount += newStatus ? 1 : -1;
    });

    if (newStatus) {
      await fsUpdateDoc('images/${component.imageId}', jsonEncode({'likeCount': WebFieldValue.increment(1)}));
      await fsSetDoc('Users/$uid/activity/likes/images/${component.imageId}', jsonEncode({
        'imageId': component.imageId,
        'likedAt': WebFieldValue.serverTimestamp()
      }), true);
    } else {
      await fsUpdateDoc('images/${component.imageId}', jsonEncode({'likeCount': WebFieldValue.increment(-1)}));
      await fsDeleteDoc('Users/$uid/activity/likes/images/${component.imageId}');
    }
  }

  @override
  Component build(BuildContext context) {
    final visibleTools = ReaderToolsConfig.tools.where((tool) {
      return ReaderToolsConfig.isToolVisibleInContext(
        tool: tool,
        userRole: 'user',
        isEditingMode: false,
        hasYoutube: component.youtubeId != null && component.youtubeId!.isNotEmpty,
        isGame: component.isGame,
        canOpenGrid: component.onOpenGrid != null,
      );
    }).toList();

    return div(classes: 'toolbar-container', [
      for (var tool in visibleTools)
        _buildToolbarButton(tool)
    ]);
  }

  Component _buildToolbarButton(ReaderTool tool) {
    bool isActive = false;
    int? count;
    VoidCallback action = () {};

    if (tool.id == 'Like') {
      isActive = _isLiked;
      count = _likeCount;
      action = _handleLike;
    } else if (tool.id == 'Comment') {
      isActive = component.activeBonusRow == BonusRowType.comments;
      count = _commentCount;
      action = () => component.onToggleBonusRow(BonusRowType.comments);
    } else if (tool.id == 'Text') {
      isActive = component.activeBonusRow == BonusRowType.textReader;
      action = () => component.onToggleBonusRow(BonusRowType.textReader);
    } else if (tool.id == 'Views') {
      count = _viewCount;
    } else if (tool.id == 'Grid') {
      action = component.onOpenGrid ?? () {};
    }

    final iconName = (isActive && tool.activeIcon != null) ? tool.activeIcon! : tool.defaultIcon;
    final resolvedIcon = iconName.replaceAll('_outlined', '');
    final btnClasses = 'toolbar-btn ${isActive ? 'active' : ''} ${tool.id == 'Like' ? 'like-btn' : ''}';

    return button(
        classes: btnClasses,
        events: {'click': (e) => action()},
        [
          div(classes: 'toolbar-icon-wrapper', [
            span(classes: 'material-symbols-outlined', [text(resolvedIcon)]),
            if (count != null && count > 0)
              span(classes: 'badge', [text('$count')])
          ]),
          span(classes: 'toolbar-label', [text(tool.label)])
        ]
    );
  }
}