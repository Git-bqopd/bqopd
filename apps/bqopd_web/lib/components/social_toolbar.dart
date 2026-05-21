import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/icon_utils.dart';

class SocialToolbar extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final String? fanzineType;
  final bool isGame;
  final String? youtubeId;
  final bool isEditingMode;
  final bool isIndiciaPage;
  final VoidCallback? onOpenGrid;
  final BonusRowType? activeBonusRow;
  final ValueChanged<BonusRowType> onToggleBonusRow;
  final Map<String, dynamic>? initialImageStats;

  const SocialToolbar({
    required this.imageId,
    this.fanzineId,
    this.fanzineType,
    this.isGame = false,
    this.youtubeId,
    this.isEditingMode = false,
    this.isIndiciaPage = false,
    this.onOpenGrid,
    required this.activeBonusRow,
    required this.onToggleBonusRow,
    this.initialImageStats,
    super.key,
  });

  @override
  State<SocialToolbar> createState() => _SocialToolbarState();
}

class _SocialToolbarState extends State<SocialToolbar> {
  int _likeCount = 0;
  int _commentCount = 0;
  bool _isLiked = false;
  String _userRole = 'user';

  dynamic _imageUnsub;
  dynamic _likeUnsub;
  dynamic _userUnsub;

  @override
  void initState() {
    super.initState();
    // VITAL: Read the SSR pre-rendered data immediately so the page is fully drawn on frame 1
    if (component.initialImageStats != null) {
      _likeCount = component.initialImageStats!['likeCount'] ?? 0;
      _commentCount = component.initialImageStats!['commentCount'] ?? 0;
    }
    // HIGH PERFORMANCE: Defer network active listeners until after the client-side compilation completes
    _deferListening();
  }

  @override
  void didUpdateComponent(SocialToolbar oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _stopListening();
      if (component.initialImageStats != null) {
        _likeCount = component.initialImageStats!['likeCount'] ?? 0;
        _commentCount = component.initialImageStats!['commentCount'] ?? 0;
      }
      _deferListening();
    }
  }

  void _deferListening() {
    if (kIsWeb) {
      // Delay listener attachment to avoid competing with image loads and main.dart.js hydration
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          _startListening();
        }
      });
    }
  }

  void _startListening() {
    if (component.imageId.isEmpty) return;

    // Listen to image stats
    _imageUnsub = fsListenDoc('images/${component.imageId}', (jsonStr) {
      final doc = jsonDecode(jsonStr);
      if (doc['exists'] && mounted) {
        final data = doc['data'];
        setState(() {
          _likeCount = data['likeCount'] ?? 0;
          _commentCount = data['commentCount'] ?? 0;
        });
      }
    });

    final uid = getCurrentUserId();
    if (uid != null) {
      _likeUnsub = fsListenDoc('Users/$uid/activity/likes/images/${component.imageId}', (jsonStr) {
        final doc = jsonDecode(jsonStr);
        if (mounted) {
          setState(() => _isLiked = doc['exists'] == true);
        }
      });

      _userUnsub = fsListenDoc('Users/$uid', (jsonStr) {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] && mounted) {
          setState(() {
            _userRole = doc['data']['role'] ?? 'user';
          });
        }
      });
    }
  }

  void _stopListening() {
    if (_imageUnsub != null) {
      try { _imageUnsub.callAsFunction(); } catch (_) {}
      _imageUnsub = null;
    }
    if (_likeUnsub != null) {
      try { _likeUnsub.callAsFunction(); } catch (_) {}
      _likeUnsub = null;
    }
    if (_userUnsub != null) {
      try { _userUnsub.callAsFunction(); } catch (_) {}
      _userUnsub = null;
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
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
        userRole: _userRole,
        isEditingMode: component.isEditingMode,
        fanzineType: component.fanzineType,
        hasYoutube: component.youtubeId != null && component.youtubeId!.isNotEmpty,
        isGame: component.isGame,
        isIndiciaPage: component.isIndiciaPage,
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
    } else if (tool.id == 'Grid') {
      action = component.onOpenGrid ?? () {};
    } else if (tool.bonusRow != null) {
      isActive = component.activeBonusRow == tool.bonusRow;
      action = () => component.onToggleBonusRow(tool.bonusRow!);
    }

    final iconName = (isActive && tool.activeIcon != null) ? tool.activeIcon! : tool.defaultIcon;
    final resolvedIcon = cleanIconName(iconName);
    final btnClasses = 'toolbar-btn ${isActive ? 'active' : ''} ${tool.id == 'Like' ? 'like-btn' : ''}';

    return button(
        classes: btnClasses,
        events: {'click': (e) => action()},
        [
          div(classes: 'toolbar-icon-wrapper', [
            span(
                classes: 'material-symbols-outlined',
                attributes: {
                  'style': isActive ? "font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;" : "font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;"
                },
                [text(resolvedIcon)]
            ),
            if (count != null && count > 0)
              span(classes: 'badge', [text('$count')])
          ]),
          span(classes: 'toolbar-label', [text(tool.label)])
        ]
    );
  }
}