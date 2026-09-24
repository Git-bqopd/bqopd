import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/web_utils.dart';

/// SocialToolbar manages the interactive social action buttons for each page item.
/// It dynamically evaluates button visibility via [ReaderToolsConfig.isToolVisibleInContext],
/// supporting public readers, makers (editors), and curator workspaces.
class SocialToolbar extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  final String? shortCode;
  final String? fanzineType;
  final int? pageNumber;
  final bool isGame;
  final String? youtubeId;
  final bool isEditingMode;
  final ToolScope? activeScope;
  final bool isIndiciaPage;
  final void Function()? onOpenGrid;
  final BonusRowType? activeBonusRow;
  final void Function(BonusRowType) onToggleBonusRow;
  final Set<String> likedImageIds;
  final Map<String, dynamic>? initialImageStats;
  final AuthState? authState;
  final AuthBloc? authBloc;

  const SocialToolbar({
    required this.imageId,
    this.fanzineId,
    this.shortCode,
    this.fanzineType,
    this.pageNumber,
    this.isGame = false,
    this.youtubeId,
    required this.isEditingMode,
    this.activeScope,
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
  int _viewCount = 0;
  bool _isLiked = false;
  bool _justCopiedShare = false;
  Timer? _copyToastTimer;
  Map<String, bool> _socialButtonVisibility = {};
  Map<String, dynamic> _imageData = {};
  dynamic _userUnsub;
  dynamic _imageStatsUnsub;

  bool get _isPreview => component.imageId.startsWith('preview_');

  /// Resolves the effective tool scope based on explicit override or reader context.
  ToolScope get effectiveScope {
    if (component.activeScope != null) return component.activeScope!;
    if (!component.isEditingMode) return ToolScope.reader;
    if (component.fanzineType == 'folio' || component.fanzineType == 'calendar') {
      return ToolScope.editor;
    }
    return ToolScope.curator;
  }

  bool get _hasTextContent {
    if (_isPreview) return true;
    final t = _imageData['text_corrected'] ?? _imageData['text'] ?? '';
    return t.toString().trim().isNotEmpty;
  }

  bool get _hasEntitiesContent {
    if (_isPreview) return true;
    final de = _imageData['detected_entities'];
    final tl = _imageData['text_corrected'] ?? '';
    final hasList = de is List && de.isNotEmpty;
    final hasBrackets = tl.toString().contains('[[') && tl.toString().contains(']]');
    return hasList || hasBrackets;
  }

  bool get _hasCreditsContent {
    if (_isPreview) return true;
    final cr = _imageData['creators'];
    final ind = _imageData['indicia'] ?? '';
    final hasCreators = cr is List && cr.isNotEmpty;
    return hasCreators || ind.toString().trim().isNotEmpty;
  }

  bool get _hasYoutubeContent {
    final yt = _imageData['youtubeId'] ?? component.youtubeId ?? '';
    return yt.toString().trim().isNotEmpty;
  }

  bool get _hasTerminalContent {
    return _imageData['isGame'] == true || component.isGame == true;
  }

  @override
  void initState() {
    super.initState();
    if (component.initialImageStats != null) {
      _likeCount = component.initialImageStats!['likeCount'] ?? 0;
      _commentCount = component.initialImageStats!['commentCount'] ?? 0;
      _viewCount = (component.initialImageStats!['regListCount'] ?? 0) +
          (component.initialImageStats!['anonListCount'] ?? 0) +
          (component.initialImageStats!['regGridCount'] ?? 0) +
          (component.initialImageStats!['anonGridCount'] ?? 0);
    }
    _isLiked = component.likedImageIds.contains(component.imageId);
    _deferListening();
  }

  @override
  void didUpdateComponent(SocialToolbar oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      if (component.initialImageStats != null) {
        _likeCount = component.initialImageStats!['likeCount'] ?? 0;
        _commentCount = component.initialImageStats!['commentCount'] ?? 0;
        _viewCount = (component.initialImageStats!['regListCount'] ?? 0) +
            (component.initialImageStats!['anonListCount'] ?? 0) +
            (component.initialImageStats!['regGridCount'] ?? 0) +
            (component.initialImageStats!['anonGridCount'] ?? 0);
      } else {
        _likeCount = 0;
        _commentCount = 0;
        _viewCount = 0;
      }
      _isLiked = component.likedImageIds.contains(component.imageId);
      _stopImageStatsListener();
      _startImageStatsListener();
    } else if (oldComponent.likedImageIds != component.likedImageIds) {
      final wasLiked = _isLiked;
      _isLiked = component.likedImageIds.contains(component.imageId);
      if (wasLiked != _isLiked) {
        _likeCount += _isLiked ? 1 : -1;
      }
    }
  }

  void _deferListening() {
    if (kIsWeb && !_isPreview) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _startListening();
          _startImageStatsListener();
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
            _socialButtonVisibility = Map<String, bool>.from(buttons);
          });
        }
      });
    }
  }

  void _startImageStatsListener() {
    if (component.imageId.isEmpty || _isPreview) return;
    _imageStatsUnsub = fsListenDoc('images/${component.imageId}', (jsonStr) {
      final doc = jsonDecode(jsonStr);
      if (doc['exists'] && mounted) {
        final data = doc['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _imageData = data;
          _likeCount = data['likeCount'] ?? 0;
          _commentCount = data['commentCount'] ?? 0;
          _viewCount = (data['regListCount'] ?? 0) +
              (data['anonListCount'] ?? 0) +
              (data['regGridCount'] ?? 0) +
              (data['anonGridCount'] ?? 0);
        });
      }
    });
  }

  void _closeListeners() {
    _stopListening();
    _stopImageStatsListener();
  }

  void _stopListening() {
    _userUnsub?.cancel();
    _userUnsub = null;
  }

  void _stopImageStatsListener() {
    _imageStatsUnsub?.cancel();
    _imageStatsUnsub = null;
  }

  @override
  void dispose() {
    _copyToastTimer?.cancel();
    _closeListeners();
    super.dispose();
  }

  Future<void> _handleLike() async {
    if (_isPreview) {
      setState(() {
        _isLiked = !_isLiked;
        _likeCount += _isLiked ? 1 : -1;
      });
      return;
    }
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

  /// Copies the clean, canonical public reader link to clipboard (stripping internal editing suffixes)
  void _handleCopyShareLink() {
    final String sc = component.shortCode ?? component.fanzineId ?? '';
    final int pNum = component.pageNumber ?? 1;

    // Canonical link assembly:
    // If on specific page (page > 1): https://bqopd.com/$shortCode/$page
    // If on cover/top (page <= 1):    https://bqopd.com/$shortCode
    String canonicalPath;
    if (pNum > 1 && sc.isNotEmpty) {
      canonicalPath = '/$sc/$pNum';
    } else if (sc.isNotEmpty) {
      canonicalPath = '/$sc';
    } else {
      canonicalPath = '';
    }

    final String origin = 'https://bqopd.com';
    final String fullUrl = '$origin$canonicalPath';

    copyToClipboard(fullUrl);

    setState(() {
      _justCopiedShare = true;
    });
    _copyToastTimer?.cancel();
    _copyToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _justCopiedShare = false;
        });
      }
    });
  }

  @override
  Component build(BuildContext context) {
    final bool hasYoutube = _hasYoutubeContent;
    final bool isGame = _hasTerminalContent;
    final bool isIndiciaPage = component.isIndiciaPage;
    final bool canOpenGrid = component.onOpenGrid != null;

    final List<ReaderTool> visibleMainTools = [];
    for (final tool in ReaderToolsConfig.tools) {
      final bool isContextuallyVisible = ReaderToolsConfig.isToolVisibleInContext(
        tool: tool,
        activeScope: effectiveScope,
        fanzineType: component.fanzineType,
        hasYoutube: hasYoutube,
        isGame: isGame,
        isIndiciaPage: isIndiciaPage,
        canOpenGrid: canOpenGrid,
      );
      if (!isContextuallyVisible) continue;

      // Section 2.C Rule: Only hide empty content tools in public reader mode!
      // In curator/maker scopes, editors must be able to add content to blank pages.
      if (!_isPreview && effectiveScope == ToolScope.reader) {
        if (tool.id == 'Text' && !_hasTextContent) continue;
        if (tool.id == 'Entities' && !_hasEntitiesContent) continue;
      }

      if (tool.id != 'Grid' && tool.id != 'Like' && tool.id != 'Settings') {
        final bool isUserVisible = _socialButtonVisibility[tool.id] ?? true;
        if (!isUserVisible) continue;
      }

      visibleMainTools.add(tool);
    }

    return div(classes: 'w-full flex-col', [
      div(classes: 'toolbar-container', [
        for (var tool in visibleMainTools)
          _buildToolbarButton(tool)
      ]),
      if (component.activeBonusRow == BonusRowType.settings)
        _buildSettingsToggleRow(
          hasYoutube: hasYoutube,
          isGame: isGame,
          isIndiciaPage: isIndiciaPage,
          canOpenGrid: canOpenGrid,
        ),
    ]);
  }

  Component _buildToolbarButton(ReaderTool tool) {
    bool isActive = false;
    int? count;
    void Function() action = () {};

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
    } else if (tool.id == 'Views') {
      isActive = component.activeBonusRow == BonusRowType.analyticsDashboard;
      count = _viewCount;
      action = () => component.onToggleBonusRow(BonusRowType.analyticsDashboard);
    } else if (tool.id == 'Share' || tool.action == ToolAction.copyShareLink) {
      isActive = _justCopiedShare;
      action = _handleCopyShareLink;
    } else if (tool.id == 'Settings') {
      isActive = component.activeBonusRow == BonusRowType.settings;
      action = () {
        if (getCurrentUserId() == null && !_isPreview) {
          GlobalModalBus.show();
        } else {
          component.onToggleBonusRow(BonusRowType.settings);
        }
      };
    } else if (tool.bonusRow != null) {
      isActive = component.activeBonusRow == tool.bonusRow;
      action = () {
        if (getCurrentUserId() == null && !_isPreview) {
          GlobalModalBus.show();
        } else {
          component.onToggleBonusRow(tool.bonusRow!);
        }
      };
    }

    final btnClasses = 'toolbar-btn ${isActive ? 'active' : ''} ${tool.id == 'Like' ? 'like-btn' : ''}';
    final iconPath = isActive ? (tool.activeIcon ?? tool.defaultIcon) : tool.defaultIcon;

    final String displayLabel = (tool.id == 'Share' && _justCopiedShare) ? 'copied!' : tool.label;

    return button(
      classes: btnClasses,
      events: {'click': (e) => action()},
      [
        div(classes: 'toolbar-icon-wrapper', [
          img(
            src: iconPath,
            attributes: const {
              'style': 'width: 18px; height: 18px; object-fit: contain; display: block;'
            },
          ),
          if (count != null && count > 0)
            span(classes: 'badge', [Component.text('$count')])
        ]),
        span(classes: 'toolbar-label', [Component.text(displayLabel)])
      ],
    );
  }

  Component _buildSettingsToggleRow({
    required bool hasYoutube,
    required bool isGame,
    required bool isIndiciaPage,
    required bool canOpenGrid,
  }) {
    final togglableTools = ReaderToolsConfig.tools.where((tool) {
      if (tool.id == 'Grid' || tool.id == 'Like' || tool.id == 'Settings') return false;
      return ReaderToolsConfig.isToolVisibleInContext(
        tool: tool,
        activeScope: effectiveScope,
        fanzineType: component.fanzineType,
        hasYoutube: hasYoutube,
        isGame: isGame,
        isIndiciaPage: isIndiciaPage,
        canOpenGrid: canOpenGrid,
      );
    }).toList();

    return div(
      classes: 'toolbar-container panel-container-animate mt-2',
      attributes: const {
        'style': 'background-color: #f9f9f9; border-top: 1px solid #eee; border-bottom: 1px solid #eee; width: 100%; box-sizing: border-box;'
      },
      [
        for (var tool in togglableTools)
          _buildSettingsToggleButton(tool)
      ],
    );
  }

  Component _buildSettingsToggleButton(ReaderTool tool) {
    bool hasContent = true;
    if (!_isPreview) {
      if (tool.id == 'Text') {
        hasContent = _hasTextContent;
      } else if (tool.id == 'Entities') {
        hasContent = _hasEntitiesContent;
      } else if (tool.id == 'Credits') {
        hasContent = _hasCreditsContent;
      } else if (tool.id == 'YouTube') {
        hasContent = _hasYoutubeContent;
      } else if (tool.id == 'Terminal') {
        hasContent = _hasTerminalContent;
      }
    }

    final bool isVisible = hasContent ? (_socialButtonVisibility[tool.id] ?? true) : false;
    final bool isToolActive = tool.bonusRow != null && component.activeBonusRow == tool.bonusRow;
    final btnClasses = 'toolbar-btn ${isToolActive ? 'active' : ''}';
    final iconPath = isToolActive ? (tool.activeIcon ?? tool.defaultIcon) : tool.defaultIcon;

    String extraStyle = '';
    if (!hasContent) {
      extraStyle = 'opacity: 0.25; filter: grayscale(100%); cursor: not-allowed;';
    } else if (!isVisible) {
      extraStyle = 'opacity: 0.35; filter: grayscale(100%);';
    }

    return button(
      classes: btnClasses,
      attributes: {
        'style': 'display: flex; flex-direction: column; align-items: center; transition: all 0.2s; $extraStyle'
      },
      events: {
        'click': (e) {
          if (hasContent) {
            _toggleButtonVisibility(tool.id);
          }
        }
      },
      [
        div(classes: 'toolbar-icon-wrapper', [
          img(
            src: iconPath,
            attributes: const {
              'style': 'width: 18px; height: 18px; object-fit: contain; display: block;'
            },
          ),
        ]),
        span(classes: 'toolbar-label', [
          Component.text(tool.label),
          if (!hasContent) span([Component.text(' (empty)')], attributes: const {'style': 'font-size: 8px; display: block;'})
        ])
      ],
    );
  }

  Future<void> _toggleButtonVisibility(String toolId) async {
    final uid = getCurrentUserId();
    final current = _socialButtonVisibility[toolId] ?? true;
    final next = !current;
    setState(() {
      _socialButtonVisibility[toolId] = next;
    });
    if (_isPreview || uid == null) return;
    await fsUpdateDoc('Users/$uid', jsonEncode({
      'preferences.socialButtons.$toolId': next
    }));
  }
}