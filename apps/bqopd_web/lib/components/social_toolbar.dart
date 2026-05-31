import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/icon_utils.dart';
import '../repositories/web_fanzine_repository.dart';

// Panel imports for local settings edit mode rendering
import 'panels/panel_container.dart';
import 'panels/text_reader_panel.dart';
import 'panels/comments_panel.dart';
import 'panels/hashtag_panel.dart';
import 'panels/master_text_panel.dart';
import 'panels/linked_text_panel.dart';
import 'panels/entities_panel.dart';
import 'panels/raw_text_panel.dart';
import 'panels/indicia_panel.dart';
import 'panels/credits_panel.dart';
import 'panels/youtube_panel.dart';
import 'panels/analytics_panel.dart';
import 'panels/publisher_text_panel.dart';

/// Highly-optimized and fully structured Social Toolbar for fanzine issues and pages.
/// Implements a double-row modular system where Row 1 reflects the standard public reader view
/// and the Settings panel toggles into "edit mode" to reveal all curator-only editor tools.
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
  final Set<String> likedImageIds; // Dynamic Set from parent layout
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
  int _viewCount = 0;
  bool _isLiked = false;
  String _userRole = 'user';
  Map<String, bool> _socialButtonVisibility = {};
  Map<String, dynamic> _imageData = {}; // Dynamic image doc metadata

  // Controls the customisation panel mode (toggled via the 'edit' button)
  bool _isSettingsEditMode = false;

  // Tracks the active editor panel inside Settings Edit Mode
  BonusRowType? _activeEditorPanel;

  // Broad listeners
  dynamic _userUnsub;
  dynamic _imageStatsUnsub;

  // Real-time Content Check Getters
  bool get _hasTextContent {
    final t = _imageData['text_corrected'] ?? _imageData['text_linked'] ?? _imageData['text_raw'] ?? _imageData['text'] ?? '';
    return t.toString().trim().isNotEmpty;
  }

  bool get _hasEntitiesContent {
    final de = _imageData['detected_entities'];
    final tl = _imageData['text_linked'] ?? '';
    final hasList = de is List && de.isNotEmpty;
    final hasBrackets = tl.toString().contains('[[') && tl.toString().contains(']]');
    return hasList || hasBrackets;
  }

  bool get _hasCreditsContent {
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

    // Sync image specific metrics and liked state
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

    // Clean up local editor panel state if settings panel is closed
    if (component.activeBonusRow != BonusRowType.settings) {
      _activeEditorPanel = null;
    }
  }

  void _deferListening() {
    if (kIsWeb) {
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
            _userRole = data['role'] ?? 'user';
            _socialButtonVisibility = Map<String, bool>.from(buttons);
          });
        }
      });
    }
  }

  void _startImageStatsListener() {
    if (component.imageId.isEmpty) return;
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
    _closeListeners();
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

  /// Master transaction handling for new publisher page generation.
  Future<void> _handleNewPageInsertion() async {
    if (component.fanzineId == null) return;

    setState(() {
      _isSettingsEditMode = true; // Stay in edit mode
    });

    try {
      final IFanzineRepository repo = WebFanzineRepository();

      // Resolve current fanzine layout pages to determine the precise "N" after-number insertion point
      final List<FanzinePage> pages = [];
      final pagesStr = await fsQuery('fanzines/${component.fanzineId}/pages', '', '', '', 'pageNumber');
      final List decoded = jsonDecode(pagesStr);
      for (var d in decoded) {
        pages.add(FanzinePage.fromMap(d['id'], d['data']));
      }

      // Locate current image's pageNumber in the list
      int currentNum = 1;
      for (var p in pages) {
        if (p.imageId == component.imageId) {
          currentNum = p.pageNumber;
          break;
        }
      }

      final initialTemplateText = """
# THE PUBLISHER
## New Custom Page Created

Start typing directly inside the text editor panel below to generate columns of printable metadata. Use images from your local library context.

{{IMAGE}}

* Enter bullet lists with an asterisk
* Customize headers with # or ##
""";

      final String newImageId = await repo.insertPublisherPage(
        component.fanzineId!,
        currentNum,
        initialTemplateText,
        pages,
      );

      // Successfully generated. Instantly open/transition focus into the new publisher page text panel!
      setState(() {
        _activeEditorPanel = BonusRowType.newPage;
      });

    } catch (e) {
      print("[PUBLISHER CREATION FAILURE] $e");
    }
  }

  @override
  Component build(BuildContext context) {
    // Row 1 (Main Row tool configurations) - Holds the static standard reader-facing social toolbar
    final mainToolIds = [
      'Grid',
      'Like',
      'Comment',
      if (_hasTextContent) 'Text',
      'Tags',
      'Views',
      'Share',
      if (_hasEntitiesContent) 'Entities',
      if (_hasCreditsContent) 'Credits',
      if (_hasYoutubeContent) 'YouTube',
      if (_hasTerminalContent) 'Terminal',
      'Settings',
    ];

    final List<ReaderTool> visibleMainTools = [];
    for (final id in mainToolIds) {
      try {
        final tool = ReaderToolsConfig.tools.firstWhere((t) => t.id == id);
        bool isContextuallyVisible = true;
        if (id == 'Grid') {
          isContextuallyVisible = component.onOpenGrid != null;
        }

        // Consult customisation visibility map for customizable toolbar buttons
        if (isContextuallyVisible && id != 'Grid' && id != 'Like' && id != 'Settings') {
          final bool isUserVisible = _socialButtonVisibility[tool.id] ?? true;
          if (!isUserVisible) {
            isContextuallyVisible = false;
          }
        }

        if (isContextuallyVisible) {
          visibleMainTools.add(tool);
        }
      } catch (_) {}
    }

    return div(classes: 'w-full flex-col', [
      // 1. Row 1: Main row of default reader tools
      div(classes: 'toolbar-container', [
        for (var tool in visibleMainTools)
          _buildToolbarButton(tool)
      ]),

      // 2. Settings/Button toggle list (Optionally renders either customizable toggles or advanced editor tools)
      if (component.activeBonusRow == BonusRowType.settings)
        _buildSettingsToggleRow(),

      if (component.activeBonusRow == BonusRowType.settings && _isSettingsEditMode && _activeEditorPanel != null)
        _buildEditorPanelContent(component.imageId)
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
    } else if (tool.id == 'Views') {
      isActive = component.activeBonusRow == BonusRowType.analyticsDashboard;
      count = _viewCount;
      action = () => component.onToggleBonusRow(BonusRowType.analyticsDashboard);
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

  Component _buildEditorToolsSubRow() {
    final editorToolIds = [
      'Raw',
      'Master',
      'Linked',
      'Entities',
      'Indicia',
      'Credits',
      'YouTube',
      'Terminal'
    ];

    final visibleEditorTools = ReaderToolsConfig.tools.where((tool) {
      if (!editorToolIds.contains(tool.id)) return false;

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
          'style': 'background-color: #fafafa; border-top: 1px solid #eee; border-bottom: 1px solid #eee; width: 100%; box-sizing: border-box;'
        },
        [
          for (var tool in visibleEditorTools)
            _buildEditorToolbarButton(tool)
        ]
    );
  }

  Component _buildEditorToolbarButton(ReaderTool tool) {
    bool isActive = component.activeBonusRow == tool.bonusRow;

    final iconName = (isActive && tool.activeIcon != null) ? tool.activeIcon! : tool.defaultIcon;
    final resolvedIcon = cleanIconName(iconName);
    final btnClasses = 'toolbar-btn ${isActive ? 'active' : ''}';

    return button(
        classes: btnClasses,
        events: {
          'click': (e) {
            if (tool.bonusRow != null) {
              component.onToggleBonusRow(tool.bonusRow!);
            }
          }
        },
        [
          div(classes: 'toolbar-icon-wrapper', [
            span(
                classes: 'material-symbols-outlined',
                attributes: {
                  'style': isActive ? "font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;" : "font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;"
                },
                [text(resolvedIcon)]
            )
          ]),
          span(classes: 'toolbar-label', [text(tool.label)])
        ]
    );
  }

  Component _buildSettingsToggleRow() {
    if (!_isSettingsEditMode) {
      // STANDARD CUSTOMIZATION MODE: Turn standard main social toolbar buttons on and off
      final togglableToolIds = [
        'Comment',
        'Text',
        'Tags',
        'Views',
        'Share',
        if (_hasEntitiesContent) 'Entities',
        if (_hasCreditsContent) 'Credits',
        if (_hasYoutubeContent) 'YouTube',
        if (_hasTerminalContent) 'Terminal',
      ];

      final List<ReaderTool> togglableTools = [];
      for (final id in togglableToolIds) {
        try {
          final tool = ReaderToolsConfig.tools.firstWhere((t) => t.id == id);
          togglableTools.add(tool);
        } catch (_) {}
      }

      return div(
          classes: 'toolbar-container panel-container-animate mt-2',
          attributes: const {
            'style': 'background-color: #f9f9f9; border-top: 1px solid #eee; border-bottom: 1px solid #eee; width: 100%; box-sizing: border-box;'
          },
          [
            for (var tool in togglableTools)
              _buildSettingsToggleButton(tool),
            if (component.isEditingMode)
              _buildEditorToggleButton() // Displays 'edit' button as the last button on the right
          ]
      );
    } else {
      // ADVANCED EDIT MODE: Instantly displays active curator action buttons
      final editorToolIds = [
        'Raw',
        'Master',
        'Linked',
        'Entities',
        'Indicia',
        'Credits',
        'YouTube',
        'Terminal'
      ];

      final List<ReaderTool> visibleEditorTools = [];
      for (final id in editorToolIds) {
        try {
          final tool = ReaderToolsConfig.tools.firstWhere((t) => t.id == id);
          visibleEditorTools.add(tool);
        } catch (_) {}
      }

      return div(
          classes: 'toolbar-container panel-container-animate mt-2',
          attributes: const {
            'style': 'background-color: #f9f9f9; border-top: 1px solid #eee; border-bottom: 1px solid #eee; width: 100%; box-sizing: border-box;'
          },
          [
            for (var tool in visibleEditorTools)
              _buildSettingsEditModeActionButton(tool),
            _buildSettingsEditModeNewPageButton(), // New page insertion action trigger
            _buildEditorToggleButton() // Displays 'edit' button as the last button on the right (marked as active)
          ]
      );
    }
  }

  Component _buildSettingsToggleButton(ReaderTool tool) {
    bool hasContent = true;
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

    final bool isVisible = hasContent ? (_socialButtonVisibility[tool.id] ?? true) : false;

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

    final btnClasses = 'toolbar-btn ${isToolActive ? 'active' : ''}';

    // Style logic: if empty, display as unclickable and greyed out
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
          span(classes: 'toolbar-label', [
            text(tool.label),
            if (!hasContent) span([text(' (empty)')], attributes: const {'style': 'font-size: 8px; display: block;'})
          ])
        ]
    );
  }

  /// Specialized action buttons loaded inside edit mode.
  /// Click behavior maintains settings panel while rendering the related panel below.
  Component _buildSettingsEditModeActionButton(ReaderTool tool) {
    final bool isActive = _activeEditorPanel == tool.bonusRow;
    final iconName = (isActive && tool.activeIcon != null) ? tool.activeIcon! : tool.defaultIcon;
    final resolvedIcon = cleanIconName(iconName);
    final btnClasses = 'toolbar-btn ${isActive ? 'active' : ''}';

    return button(
        classes: btnClasses,
        attributes: const {
          'style': 'display: flex; flex-direction: column; align-items: center; cursor: pointer; transition: all 0.2s;'
        },
        events: {
          'click': (e) {
            if (tool.bonusRow != null) {
              setState(() {
                _activeEditorPanel = (_activeEditorPanel == tool.bonusRow) ? null : tool.bonusRow;
              });
            }
          }
        },
        [
          div(classes: 'toolbar-icon-wrapper', [
            span(
                classes: 'material-symbols-outlined',
                attributes: {
                  'style': isActive ? "font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;" : "font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;"
                },
                [text(resolvedIcon)]
            )
          ]),
          span(classes: 'toolbar-label', [text(tool.label)])
        ]
    );
  }

  /// Unique settings panel button trigger specifically targeting instant 'new page' insertion.
  Component _buildSettingsEditModeNewPageButton() {
    final bool isActive = _activeEditorPanel == BonusRowType.newPage;
    final resolvedIcon = cleanIconName('note_add');
    final btnClasses = 'toolbar-btn ${isActive ? 'active' : ''}';

    return button(
        classes: btnClasses,
        attributes: const {
          'style': 'display: flex; flex-direction: column; align-items: center; cursor: pointer; transition: all 0.2s;'
        },
        events: {
          'click': (e) => _handleNewPageInsertion()
        },
        [
          div(classes: 'toolbar-icon-wrapper', [
            span(
                classes: 'material-symbols-outlined',
                attributes: {
                  'style': isActive ? "font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;" : "font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;"
                },
                [text(resolvedIcon)]
            )
          ]),
          span(classes: 'toolbar-label', [text('new page')])
        ]
    );
  }

  /// Specialized toggle button for the Editor Row.
  /// Toggles the settings panel into 'edit mode' to reveal advanced options.
  Component _buildEditorToggleButton() {
    final bool isToolActive = _isSettingsEditMode;
    final resolvedIcon = cleanIconName('construction');
    final btnClasses = 'toolbar-btn ${isToolActive ? 'active' : ''}';

    return button(
        classes: btnClasses,
        attributes: const {
          'style': 'display: flex; flex-direction: column; align-items: center; cursor: pointer; transition: all 0.2s;'
        },
        events: {
          'click': (e) {
            setState(() {
              _isSettingsEditMode = !_isSettingsEditMode;
              if (!_isSettingsEditMode) {
                _activeEditorPanel = null;
              }
            });
          }
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
            )
          ]),
          span(classes: 'toolbar-label', [text('edit')])
        ]
    );
  }

  /// Helper to dynamically render our selected editor panels below standard toolbar elements
  Component _buildEditorPanelContent(String imageId) {
    Component inner;
    String title = "";

    switch (_activeEditorPanel!) {
      case BonusRowType.rawText:
        title = "Raw OCR Text";
        inner = RawTextPanel(imageId: imageId);
        break;
      case BonusRowType.masterText:
        title = ""; // Omit the 'CORRECTED TEXT EDITOR' title
        inner = MasterTextPanel(imageId: imageId, fanzineId: component.fanzineId ?? '');
        break;
      case BonusRowType.linkedText:
        title = ""; // Omit the 'WIKI-LINK EDITOR' title
        inner = LinkedTextPanel(imageId: imageId, fanzineId: component.fanzineId ?? '');
        break;
      case BonusRowType.entities:
        title = ""; // Omit 'PAGE ENTITIES' text
        inner = EntitiesPanel(imageId: imageId, fanzineId: component.fanzineId, isEditingMode: component.isEditingMode);
        break;
      case BonusRowType.indicia:
        title = "Issue Indicia";
        inner = IndiciaPanel(fanzineId: component.fanzineId ?? '', isEditingMode: component.isEditingMode);
        break;
      case BonusRowType.credits:
        title = "Creators";
        inner = CreditsPanel(imageId: imageId);
        break;
      case BonusRowType.youtube:
        title = "Video Resource";
        inner = YoutubePanel(imageId: imageId);
        break;
      case BonusRowType.views:
      case BonusRowType.analyticsDashboard:
        title = "Analytics Dashboard";
        inner = AnalyticsPanel(imageId: imageId);
        break;
      case BonusRowType.newPage:
        title = "New Page Text Editor";
        inner = PublisherTextPanel(imageId: imageId);
        break;
      case BonusRowType.terminal:
        title = "Terminal Game";
        inner = div([
          p(classes: 'text-center text-sm text-gray p-6 italic', [
            text('CA Combat Terminal is optimized only for mobile application contexts.')
          ])
        ]);
        break;
      default:
        return div([]);
    }

    return PanelContainer(
      title: title,
      type: _activeEditorPanel!,
      child: inner,
    );
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
}