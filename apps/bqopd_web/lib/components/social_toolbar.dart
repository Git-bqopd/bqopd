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
  final Set<String> likedImageIds; // Dynamic Set from parent
  final Map<String, dynamic>? initialImageStats;
  final AuthState? authState;
  final AuthBloc? authBloc;

  const SocialToolbar({
    required this.imageId,
    this.fanzineId,
    this.fanzineType,
    this.isGame = false,
    this.youtubeId,
    required this.isEditingMode,
    this.isIndiciaPage = false,
    this.onOpenGrid,
    required this.activeBonusRow,
    required this.onToggleBonusRow,
    required this.likedImageIds,
    this.initialImageStats,
    this.authState,
    this.authBloc,
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
  Map<String, bool> _socialButtonVisibility = {};

  // HIGH PERFORMANCE: Eradicated separate document listeners to prevent client-side "Listener Storm"
  dynamic _userUnsub;

  @override
  void initState() {
    super.initState();
    if (component.initialImageStats != null) {
      _likeCount = component.initialImageStats!['likeCount'] ?? 0;
      _commentCount = component.initialImageStats!['commentCount'] ?? 0;
    }
    _isLiked = component.likedImageIds.contains(component.imageId);

    _deferListening();
  }

  @override
  void didUpdateComponent(SocialToolbar oldComponent) {
    super.didUpdateComponent(oldComponent);

    // Reset back to initial preloaded stats ONLY if the active imageId has changed
    if (oldComponent.imageId != component.imageId) {
      if (component.initialImageStats != null) {
        _likeCount = component.initialImageStats!['likeCount'] ?? 0;
        _commentCount = component.initialImageStats!['commentCount'] ?? 0;
      } else {
        _likeCount = 0;
        _commentCount = 0;
      }
      _isLiked = component.likedImageIds.contains(component.imageId);
    }
    // If the image remains the same but the liked set changes, adjust the count dynamically
    else if (oldComponent.likedImageIds != component.likedImageIds) {
      final wasLiked = _isLiked;
      _isLiked = component.likedImageIds.contains(component.imageId);
      if (wasLiked != _isLiked) {
        _likeCount += _isLiked ? 1 : -1;
      }
    }
  }

  void _deferListening() {
    if (kIsWeb) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _startListening();
        }
      });
    }
  }

  void _startListening() {
    final uid = getCurrentUserId();
    if (uid != null) {
      _userUnsub = fsListenDoc('Users/$uid', (jsonStr) {
        final doc = jsonDecode(jsonStr);
        if (doc['exists'] && mounted) {
          final data = doc['data'] as Map<String, dynamic>? ?? {};
          final prefs = data['preferences'] as Map<String, dynamic>? ?? {};
          final buttons = prefs['socialButtons'] as Map<String, dynamic>? ?? {};
          setState(() {
            _userRole = data['role'] ?? 'user';
            _socialButtonVisibility = Map<String, bool>.from(buttons);
          });
        }
      });
    }
  }

  void _stopListening() {
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
    if (uid == null) {
      GlobalModalBus.show();
      return;
    }

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

  Future<void> _toggleButtonVisibility(String toolId) async {
    final uid = getCurrentUserId();
    if (uid == null) {
      GlobalModalBus.show();
      return;
    }

    final current = _socialButtonVisibility[toolId] ?? true;
    final next = !current;

    setState(() {
      _socialButtonVisibility[toolId] = next;
    });

    await fsUpdateDoc('Users/$uid', jsonEncode({
      'preferences.socialButtons.$toolId': next
    }));
  }

  @override
  Component build(BuildContext context) {
    final visibleTools = ReaderToolsConfig.tools.where((tool) {
      // EXCLUDE raw and views editor buttons in the Jaspr Web App
      if (tool.id == 'Raw' || tool.id == 'Views') {
        return false;
      }

      // FORCE show the 'Settings' (buttons), 'Grid' (open), and 'Like' (like) buttons unconditionally
      if (tool.id == 'Settings' || tool.id == 'Grid' || tool.id == 'Like') {
        return true;
      }

      // CHECK user preference to decide if this button is visible in the main bar
      final bool isUserVisible = _socialButtonVisibility[tool.id] ?? true;
      if (!isUserVisible) {
        return false;
      }

      // FORCE show the 'Entities' tool unconditionally so users can always interact with page references
      if (tool.id == 'Entities') {
        return true;
      }

      // FORCE show the 'Master' (corrected text editor) and 'Linked' (wiki-link editor) tools if we are in editing mode
      if (tool.id == 'Master' || tool.id == 'Linked') {
        return component.isEditingMode;
      }

      // FORCE show the 'Indicia' button unconditionally if selected by user
      if (tool.id == 'Indicia') {
        return true;
      }

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

    return div(classes: 'w-full flex-col', [
      div(classes: 'toolbar-container', [
        for (var tool in visibleTools)
          _buildToolbarButton(tool)
      ]),
      if (component.activeBonusRow == BonusRowType.settings)
        _buildSettingsToggleRow()
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
      action = () {
        if (tool.id == 'Settings' && getCurrentUserId() == null) {
          GlobalModalBus.show();
        } else {
          component.onToggleBonusRow(tool.bonusRow!);
        }
      };
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

  Component _buildSettingsToggleRow() {
    final togglableTools = ReaderToolsConfig.tools.where((tool) {
      // EXCLUDE core/fixed buttons from the customisation toggles row
      if (tool.id == 'Settings' || tool.id == 'Grid' || tool.id == 'Like') return false;
      if (tool.id == 'Raw' || tool.id == 'Views') return false;

      // Unconditionally include Entities as always available for toggle
      if (tool.id == 'Entities') {
        return true;
      }

      // Contextually include Master (corrected), Linked (linked), and Indicia (indicia) in editing mode
      if (tool.id == 'Master' || tool.id == 'Linked' || tool.id == 'Indicia') {
        return component.isEditingMode;
      }

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

    return div(
        classes: 'toolbar-container panel-container-animate mt-2',
        attributes: {
          'style': 'background-color: #f9f9f9; border-top: 1px solid #eee; border-bottom: 1px solid #eee; width: 100%; box-sizing: border-box;'
        },
        [
          for (var tool in togglableTools)
            _buildSettingsToggleButton(tool)
        ]
    );
  }

  Component _buildSettingsToggleButton(ReaderTool tool) {
    final bool isVisible = _socialButtonVisibility[tool.id] ?? true;

    bool isToolActive = false;
    int? toolCount;

    if (tool.id == 'Like') {
      isToolActive = _isLiked;
      toolCount = _likeCount;
    } else if (tool.id == 'Comment') {
      isToolActive = component.activeBonusRow == BonusRowType.comments;
      toolCount = _commentCount;
    } else if (tool.id == 'Text') {
      isToolActive = component.activeBonusRow == BonusRowType.textReader;
    } else if (tool.bonusRow != null) {
      isToolActive = component.activeBonusRow == tool.bonusRow;
    }

    final iconName = (isToolActive && tool.activeIcon != null) ? tool.activeIcon! : tool.defaultIcon;
    final resolvedIcon = cleanIconName(iconName);

    final btnClasses = 'toolbar-btn ${isToolActive ? 'active' : ''} ${tool.id == 'Like' ? 'like-btn' : ''} ${!isVisible ? 'greyed-out' : ''}';
    final String extraStyle = !isVisible ? 'opacity: 0.35; filter: grayscale(100%);' : '';

    return button(
        classes: btnClasses,
        attributes: {
          'style': 'display: flex; flex-direction: column; align-items: center; cursor: pointer; transition: all 0.2s; $extraStyle'
        },
        events: {
          'click': (e) => _toggleButtonVisibility(tool.id)
        },
        [
          div(classes: 'toolbar-icon-wrapper', [
            span(
                classes: 'material-symbols-outlined',
                attributes: {
                  'style': isToolActive
                      ? "font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;"
                      : "font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;"
                },
                [text(resolvedIcon)]
            ),
            if (toolCount != null && toolCount > 0)
              span(classes: 'badge', [text('$toolCount')])
          ]),
          span(classes: 'toolbar-label', [text(tool.label)])
        ]
    );
  }
}