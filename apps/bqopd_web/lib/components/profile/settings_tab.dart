import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../utils/icon_utils.dart';
import '../editor/modals/confirm_modal.dart';

/// Unified utility to normalize handles consistently across settings, curator, and entities directory.
String normalizeHandle(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
}

/// Customizable toolbar configurations, managed profiles form, global default shortcodes, and administrator role parameters.
class ProfileSettingsTab extends StatefulComponent {
  final UserAccount? viewerAccount;
  final String targetUserId;
  final bool isMe;
  final IUserRepository userRepository;
  final int initialSubTab;
  final ValueChanged<int> onSubTabChanged;

  const ProfileSettingsTab({
    required this.viewerAccount,
    required this.targetUserId,
    required this.isMe,
    required this.userRepository,
    required this.initialSubTab,
    required this.onSubTabChanged,
    super.key,
  });

  @override
  State<ProfileSettingsTab> createState() => _ProfileSettingsTabState();
}

class _ProfileSettingsTabState extends State<ProfileSettingsTab> {
  int _activeSubTab = 0; // 0: shortcodes, 1: managed profiles, 2: permissions, 3: social buttons
  Map<String, bool> _socialButtonVisibility = {};

  // Active matrix feature/question column filters
  final Set<String> _activeMatrixColumns = {'position', 'reader', 'maker'};

  static const Map<String, String> _matrixColumnLabels = {
    'position': 'position',
    'reader': 'fanzine reader',
    'maker': 'maker / editor',
    'curator': 'curator pipeline',
    'guests': 'public guests',
  };

  // Simplified Drag and Drop State
  List<ReaderTool> _orderedTools = [];
  int? _draggedIndex;

  // Create Managed Profile Inputs
  String _newManagedFirstName = '';
  String _newManagedLastName = '';
  String _newManagedBio = '';
  bool _isCreatingManagedProfile = false;
  String? _managedProfileFeedback;
  bool _isManagedProfileError = false;

  // Deletion Modal State
  String? _pendingDeleteProfileId;
  String? _pendingDeleteProfileUsername;
  String? _pendingDeleteProfileDisplayName;

  // Global shortcode configurations
  String _loginZineShortcode = '';
  String _registerZineShortcode = '';
  bool _isSavingSettings = false;
  String? _settingsFeedback;
  bool _isSettingsError = false;

  // Real-time Managed profiles streams
  List<Map<String, dynamic>> _managedProfiles = [];
  bool _loadingManaged = true;
  FirebaseSubscription? _managedSub;

  // Real-time User Accounts list
  List<Map<String, dynamic>> _allSystemUsers = [];
  bool _loadingUsers = true;
  FirebaseSubscription? _usersSub;

  // Notification feedbacks for operations
  String? _permissionFeedback;
  String? _permissionFeedbackUid;

  @override
  void initState() {
    super.initState();
    _activeSubTab = component.initialSubTab;
    _initOrderedTools();

    if (component.viewerAccount != null && component.viewerAccount!.preferences.containsKey('socialButtons')) {
      _socialButtonVisibility = Map<String, bool>.from(component.viewerAccount!.preferences['socialButtons']);
    }
    _loadGlobalSettings();
    if (kIsWeb) {
      Future.microtask(() {
        if (mounted) {
          _listenToManagedProfiles();
          _listenToSystemUsers();
        }
      });
    }
  }

  void _initOrderedTools() {
    final defaultTools = List<ReaderTool>.from(ReaderToolsConfig.tools);
    // Guarantee 'buttons' (Settings) is placed at the very end as the furthest right toolbar button
    final settingsIdx = defaultTools.indexWhere((t) => t.id == 'Settings');
    if (settingsIdx != -1 && settingsIdx != defaultTools.length - 1) {
      final settingsTool = defaultTools.removeAt(settingsIdx);
      defaultTools.add(settingsTool);
    }

    if (component.viewerAccount != null && component.viewerAccount!.preferences.containsKey('socialButtonsOrder')) {
      final List savedOrder = component.viewerAccount!.preferences['socialButtonsOrder'] as List? ?? [];
      if (savedOrder.isNotEmpty) {
        final Map<String, ReaderTool> toolMap = {for (var t in defaultTools) t.id: t};
        final List<ReaderTool> sorted = [];
        for (var id in savedOrder) {
          if (toolMap.containsKey(id.toString())) {
            sorted.add(toolMap.remove(id.toString())!);
          }
        }
        sorted.addAll(toolMap.values);
        _orderedTools = sorted;
        return;
      }
    }
    _orderedTools = defaultTools;
  }

  @override
  void didUpdateComponent(ProfileSettingsTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialSubTab != component.initialSubTab) {
      _activeSubTab = component.initialSubTab;
    }
    if (oldComponent.targetUserId != component.targetUserId && kIsWeb) {
      _listenToManagedProfiles();
      _listenToSystemUsers();
    }
    if (component.viewerAccount != null && oldComponent.viewerAccount == null) {
      if (component.viewerAccount!.preferences.containsKey('socialButtons')) {
        _socialButtonVisibility = Map<String, bool>.from(component.viewerAccount!.preferences['socialButtons']);
      }
      _initOrderedTools();
    }
  }

  @override
  void dispose() {
    _managedSub?.callAsFunction();
    _usersSub?.callAsFunction();
    super.dispose();
  }

  Future<void> _loadGlobalSettings() async {
    try {
      final res = await fsGetDoc('app_settings/main_settings');
      final doc = jsonDecode(res);
      if (doc['exists'] == true) {
        setState(() {
          _loginZineShortcode = doc['data']['login_zine_shortcode'] ?? '';
          _registerZineShortcode = doc['data']['register_zine_shortcode'] ?? '';
        });
      }
    } catch (e) {
      print("Error loading global settings: $e");
    }
  }

  void _listenToManagedProfiles() {
    _managedSub?.callAsFunction();
    _managedSub = null;
    setState(() => _loadingManaged = true);
    _managedSub = fsListenQuery('profiles', '', '', '', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final Map<String, Map<String, dynamic>> uniqueProfiles = {};
        for (var d in decoded) {
          final data = d['data'] as Map<String, dynamic>? ?? {};
          final String id = d['id'] as String? ?? '';
          if (id.isEmpty) continue;
          data['id'] = id;
          final List managers = data['managers'] ?? [];
          final String username = (data['username'] ?? '').toString().trim().toLowerCase();
          if (managers.contains(component.targetUserId)) {
            final String key = username.isNotEmpty ? username : id;
            if (!uniqueProfiles.containsKey(key)) {
              uniqueProfiles[key] = data;
            }
          }
        }
        final profiles = uniqueProfiles.values.toList();
        if (mounted) {
          setState(() {
            _managedProfiles = profiles;
            _loadingManaged = false;
          });
        }
      } catch (e) {
        print("Error parsing managed profiles: $e");
        if (mounted) setState(() => _loadingManaged = false);
      }
    });
  }

  void _listenToSystemUsers() {
    _usersSub?.callAsFunction();
    _usersSub = null;
    setState(() => _loadingUsers = true);
    _usersSub = fsListenQuery('Users', '', '', '', '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final users = decoded.map((d) {
          final data = d['data'] as Map<String, dynamic>;
          data['id'] = d['id'];
          return data;
        }).toList();
        if (mounted) {
          setState(() {
            _allSystemUsers = users;
            _loadingUsers = false;
          });
        }
      } catch (e) {
        print("Error loading users: $e");
        if (mounted) setState(() => _loadingUsers = false);
      }
    });
  }

  Future<void> _saveGlobalSettings() async {
    setState(() {
      _isSavingSettings = true;
      _settingsFeedback = "Saving global settings...";
      _isSettingsError = false;
    });
    try {
      await fsSetDoc('app_settings/main_settings', jsonEncode({
        'login_zine_shortcode': _loginZineShortcode.trim(),
        'register_zine_shortcode': _registerZineShortcode.trim()
      }), true);
      setState(() {
        _settingsFeedback = 'Global settings updated successfully!';
        _isSettingsError = false;
      });
    } catch (e) {
      print("Error saving global settings: $e");
      setState(() {
        _settingsFeedback = 'Failed to save settings: ${e.toString()}';
        _isSettingsError = true;
      });
    }
    setState(() => _isSavingSettings = false);
  }

  Future<void> _createManagedProfile() async {
    if (_newManagedFirstName.trim().isEmpty || _newManagedLastName.trim().isEmpty) {
      setState(() {
        _managedProfileFeedback = "First name and Last name are required.";
        _isManagedProfileError = true;
      });
      return;
    }
    setState(() {
      _isCreatingManagedProfile = true;
      _managedProfileFeedback = "Generating managed profile identity...";
      _isManagedProfileError = false;
    });
    try {
      final String baseHandle = normalizeHandle("${_newManagedFirstName.trim()} ${_newManagedLastName.trim()}");
      final String uniqueId = 'managed_${DateTime.now().millisecondsSinceEpoch}';
      final publicData = {
        'uid': uniqueId,
        'username': baseHandle,
        'displayName': "${_newManagedFirstName.trim()} ${_newManagedLastName.trim()}",
        'bio': _newManagedBio.trim(),
        'photoUrl': '',
        'isManaged': true,
        'isCurator': false,
        'isAdmin': false,
        'managers': [component.targetUserId],
        'followerCount': 0,
        'followingCount': 0,
        'updatedAt': WebFieldValue.serverTimestamp()
      };
      await fsSetDoc('profiles/$uniqueId', jsonEncode(publicData), true);
      await fsSetDoc('usernames/$baseHandle', jsonEncode({
        'uid': uniqueId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);
      await fsSetDoc('shortcodes/${baseHandle.toUpperCase()}', jsonEncode({
        'type': 'user',
        'contentId': uniqueId,
        'displayCode': baseHandle,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);
      setState(() {
        _newManagedFirstName = '';
        _newManagedLastName = '';
        _newManagedBio = '';
        _isCreatingManagedProfile = false;
        _managedProfileFeedback = "Managed profile @$baseHandle initialized successfully!";
        _isManagedProfileError = false;
      });
    } catch (e) {
      print("Error creating managed profile: $e");
      setState(() {
        _isCreatingManagedProfile = false;
        _managedProfileFeedback = "Failed to initialize: ${e.toString()}";
        _isManagedProfileError = true;
      });
    }
  }

  Future<void> _deleteManagedProfile(String id, String username) async {
    setState(() {
      _managedProfileFeedback = "Deleting managed profile @$username...";
      _isManagedProfileError = false;
    });
    try {
      final cleanUsername = username.trim().toLowerCase();
      final profileDocId = id.isNotEmpty ? id : cleanUsername;
      final List<Future<void>> deletions = [
        fsDeleteDoc('profiles/$profileDocId'),
      ];
      if (cleanUsername.isNotEmpty) {
        deletions.add(fsDeleteDoc('usernames/$cleanUsername'));
        deletions.add(fsDeleteDoc('shortcodes/${cleanUsername.toUpperCase()}'));
      }
      await Future.wait(deletions);
      setState(() {
        _managedProfileFeedback = "Managed profile @$username deleted successfully.";
        _isManagedProfileError = false;
      });
    } catch (e) {
      print("[SETTINGS TAB] Error deleting managed profile: $e");
      setState(() {
        _managedProfileFeedback = "Failed to delete: ${e.toString()}";
        _isManagedProfileError = true;
      });
    }
  }

  Future<void> _updateUserPermission(String uid, String newRole) async {
    setState(() {
      _permissionFeedbackUid = uid;
      _permissionFeedback = "Updating access levels...";
    });
    try {
      final bool isCurator = newRole == 'curator' || newRole == 'admin' || newRole == 'moderator';
      await fsUpdateDoc('Users/$uid', jsonEncode({
        'role': newRole,
        'isCurator': isCurator
      }));
      await fsUpdateDoc('profiles/$uid', jsonEncode({
        'isCurator': isCurator,
        'isAdmin': newRole == 'admin'
      }));
      setState(() {
        _permissionFeedback = "Access privileges saved!";
      });
    } catch (e) {
      setState(() {
        _permissionFeedback = "Update failed: ${e.toString()}";
      });
    }
  }

  void _reorderTool(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _orderedTools.length) return;
    if (newIndex < 0 || newIndex >= _orderedTools.length) return;
    if (oldIndex == newIndex) return;
    setState(() {
      final tool = _orderedTools.removeAt(oldIndex);
      _orderedTools.insert(newIndex, tool);
    });
    _saveToolOrder();
  }

  Future<void> _saveToolOrder() async {
    final orderIds = _orderedTools.map((t) => t.id).toList();
    await fsUpdateDoc('Users/${component.targetUserId}', jsonEncode({
      'preferences.socialButtonsOrder': orderIds
    }));
  }

  /// Renders selectable chips for feature columns and a matrix grid of cards with toggle switches.
  Component _buildSocialButtonsSettingsView() {
    return div(
        [
          // 1. Selectable Chips Row (Feature / Option Column Toggles)
          div(
            classes: 'flex-col gap-2 w-full mb-4',
            attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%; margin-bottom: 16px;'},
            [
              span(
                  [text("FEATURE / CONTEXT COLUMNS")],
                  attributes: const {
                    'style': 'font-size: 11px; font-weight: bold; color: #6b7280; text-transform: uppercase; letter-spacing: 0.5px;'
                  }
              ),
              div(
                classes: 'flex-row flex-wrap gap-2 items-center',
                attributes: const {'style': 'display: flex; flex-wrap: wrap; gap: 8px; align-items: center;'},
                [
                  for (var colKey in _matrixColumnLabels.keys)
                    _buildColumnChip(colKey, _matrixColumnLabels[colKey]!)
                ],
              ),
            ],
          ),

          // 2. Matrix Table Header (rendered when columns are selected)
          if (_activeMatrixColumns.isNotEmpty)
            div(
                attributes: const {
                  'style': 'display: flex; flex-direction: row; align-items: center; padding: 0 12px 8px 12px; border-bottom: 2px solid #e5e7eb; width: 100%; box-sizing: border-box;'
                },
                [
                  div([text("BUTTON / PANEL")], attributes: const {'style': 'flex: 1; font-size: 11px; font-weight: bold; color: #6b7280; text-transform: uppercase;'}),
                  for (var colKey in _activeMatrixColumns)
                    div(
                        [text(_matrixColumnLabels[colKey] ?? colKey)],
                        attributes: const {
                          'style': 'width: 110px; text-align: center; font-size: 10px; font-weight: bold; color: #6b7280; text-transform: uppercase; flex-shrink: 0; padding: 0 4px;'
                        }
                    )
                ]
            ),

          // 3. Card Rows List / Matrix
          div(
            classes: 'flex-col gap-2 w-full',
            attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'},
            [
              for (int i = 0; i < _orderedTools.length; i++)
                _buildSocialButtonCardRow(_orderedTools[i], i),
            ],
          )
        ],
        classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px; padding: 24px; background: white; box-sizing: border-box;'}
    );
  }

  /// Renders an individual column chip toggle for selecting feature/context columns.
  Component _buildColumnChip(String colKey, String label) {
    final bool isSelected = _activeMatrixColumns.contains(colKey);
    return button(
      classes: isSelected ? 'm3-chip active' : 'm3-chip',
      attributes: {
        'type': 'button',
        'style': 'height: 28px; padding: 0 12px; font-size: 11px; font-weight: bold; border-radius: 100px; cursor: pointer; text-transform: lowercase; border: ${isSelected ? "none" : "1px solid #79747E"}; background-color: ${isSelected ? "#E8DEF8" : "#ffffff"}; color: ${isSelected ? "#1D192B" : "#49454F"}; display: inline-flex; align-items: center; gap: 4px;',
      },
      events: {
        'click': (e) {
          setState(() {
            if (isSelected) {
              _activeMatrixColumns.remove(colKey);
            } else {
              _activeMatrixColumns.add(colKey);
            }
          });
        }
      },
      [
        if (isSelected)
          span(
              classes: 'material-symbols-outlined',
              attributes: const {'style': 'font-size: 14px; color: #1D192B;'},
              [text('check')]
          ),
        text(label),
      ],
    );
  }

  /// Renders an individual social button row card with grabber or intersection cell switches.
  Component _buildSocialButtonCardRow(ReaderTool tool, int index) {
    final iconPath = tool.defaultIcon;
    final bool isSvgAsset = iconPath.endsWith('.svg') || iconPath.startsWith('assets/');
    final bool isDragging = _draggedIndex == index;

    return div(
        classes: 'social-button-card-row',
        attributes: {
          'draggable': 'true',
          'style': 'display: flex; flex-direction: row; align-items: center; gap: 12px; padding: 8px 12px; background-color: #ffffff; border: ${isDragging ? "2px solid #6750A4" : "1px solid #e5e7eb"}; border-radius: 8px; min-height: 48px; box-sizing: border-box; width: 100%; transition: transform 0.15s ease, border-color 0.15s; cursor: grab; opacity: 1.0;',
        },
        events: {
          'dragstart': (dynamic e) {
            _draggedIndex = index;
          },
          'dragover': (dynamic e) {
            try { e.preventDefault(); } catch (_) {}
          },
          'drop': (dynamic e) {
            try { e.preventDefault(); } catch (_) {}
            if (_draggedIndex != null && _draggedIndex != index) {
              final targetIdx = _draggedIndex!;
              _draggedIndex = null;
              _reorderTool(targetIdx, index);
            } else {
              _draggedIndex = null;
            }
          },
          'dragend': (dynamic e) {
            _draggedIndex = null;
          }
        },
        [
          // 1. Social Button Icon Preview (circular border matching reader toolbar)
          div(
              attributes: const {
                'style': 'display: flex; align-items: center; justify-content: center; width: 34px; height: 34px; border-radius: 50%; border: 1.5px solid #000; flex-shrink: 0; background-color: #ffffff;'
              },
              [
                if (isSvgAsset)
                  img(
                      src: iconPath,
                      attributes: const {
                        'style': 'width: 18px; height: 18px; object-fit: contain; display: block;'
                      }
                  )
                else
                  span(
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style': 'font-size: 18px; color: #000; line-height: 1;'
                      },
                      [text(cleanIconName(iconPath))]
                  )
              ]
          ),
          // 2. Name & Description Text Container
          div(
              attributes: const {
                'style': 'display: flex; flex-direction: column; justify-content: center; flex: 1; overflow: hidden;'
              },
              [
                div(
                    [text(tool.label.toLowerCase())],
                    attributes: const {
                      'style': 'font-size: 13px; font-weight: bold; color: #000; line-height: 1.2; text-transform: lowercase;'
                    }
                ),
                div(
                    [text(tool.description)],
                    attributes: const {
                      'style': 'font-size: 11px; color: #6b7280; line-height: 1.3; margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
                    }
                )
              ]
          ),
          // 3. Cells for each active column (Position grabber or Yes/No switch)
          for (var colKey in _activeMatrixColumns)
            div(
                attributes: const {
                  'style': 'width: 110px; display: flex; justify-content: center; align-items: center; flex-shrink: 0;'
                },
                [
                  if (colKey == 'position')
                    _buildGrabberCell(index)
                  else
                    _buildCellSwitch(tool.id, colKey)
                ]
            )
        ]
    );
  }

  /// Renders a grabber handle cell for drag-and-drop position reordering.
  Component _buildGrabberCell(int index) {
    return div(
        attributes: const {
          'style': 'display: flex; align-items: center; justify-content: center; cursor: grab; user-select: none;'
        },
        [
          span(
              classes: 'material-symbols-outlined text-gray-400',
              attributes: const {'style': 'font-size: 20px; color: #9ca3af;'},
              [text('drag_indicator')]
          ),
        ]
    );
  }

  /// Renders a switch control inside an intersection matrix cell.
  Component _buildCellSwitch(String toolId, String colKey) {
    final key = '${colKey}_$toolId';
    final bool isEnabled = _socialButtonVisibility[key] ?? _getDefaultToolVisibility(toolId, colKey);

    return div(
        [
          div(
              [],
              attributes: {
                'style': 'width: 18px; height: 18px; border-radius: 50%; background-color: white; transition: left 0.2s; position: absolute; left: ${isEnabled ? '21px' : '3px'}; top: 2px; box-shadow: 0 1px 2px rgba(0,0,0,0.2);'
              }
          )
        ],
        attributes: {
          'style': 'width: 42px; height: 22px; border-radius: 100px; padding: 2px; position: relative; transition: background 0.2s; cursor: pointer; box-sizing: border-box; flex-shrink: 0; background-color: ${isEnabled ? '#6750A4' : '#ccc'};'
        },
        events: {
          'click': (e) => _toggleMatrixSwitch(toolId, colKey)
        }
    );
  }

  bool _getDefaultToolVisibility(String toolId, String colKey) {
    if (colKey == 'guests') {
      return toolId == 'Like' || toolId == 'Comment' || toolId == 'Text' || toolId == 'Grid';
    }
    return true;
  }

  Future<void> _toggleMatrixSwitch(String toolId, String colKey) async {
    final key = '${colKey}_$toolId';
    final currentVal = _socialButtonVisibility[key] ?? _getDefaultToolVisibility(toolId, colKey);
    final nextVal = !currentVal;
    setState(() {
      _socialButtonVisibility[key] = nextVal;
    });
    await fsUpdateDoc('Users/${component.targetUserId}', jsonEncode({
      'preferences.socialButtons.$key': nextVal
    }));
  }

  Component _buildManagedProfilesSettingsView() {
    return div(
        [
          div(
            [
              h3([text("Create Managed Identity (Human or Estate)")], classes: 'font-bold text-sm text-black', attributes: const {'style': 'margin-top: 0;'}),
              p([text("Initialize dedicated gallery portfolios representing historical creators or archives you manage.")], classes: 'text-xs text-gray italic mb-2', attributes: const {'style': 'margin: 0 0 8px 0;'}),
              div(
                [
                  input(attributes: {'placeholder': 'First Name', 'value': _newManagedFirstName, 'style': 'margin-bottom: 0; background: white;'}, events: {'input': (e) => _newManagedFirstName = getInputValue(e)}),
                  span([], attributes: const {'style': 'display: inline-block; width: 12px;'}),
                  input(attributes: {'placeholder': 'Last Name', 'value': _newManagedLastName, 'style': 'margin-bottom: 0; background: white;'}, events: {'input': (e) => _newManagedLastName = getInputValue(e)}),
                ],
                attributes: const {'style': 'display: flex; gap: 12px; width: 100%; box-sizing: border-box;'},
              ),
              input(attributes: {'placeholder': 'Identity Biography / Historical Context', 'value': _newManagedBio, 'style': 'margin-bottom: 0; background: white;'}, events: {'input': (e) => _newManagedBio = getInputValue(e)},),
              if (_managedProfileFeedback != null)
                p([text(_managedProfileFeedback!)], attributes: {
                  'style': 'font-size: 12px; font-weight: bold; margin: 4px 0; color: ${_isManagedProfileError ? "#ef4444" : "#16a34a"}'
                }),
              button(
                  [text(_isCreatingManagedProfile ? "initializing..." : "create profile")],
                  classes: 'btn-primary nav-pill',
                  attributes: _isCreatingManagedProfile
                      ? const {'disabled': 'true', 'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; width: 180px;'}
                      : const {'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; width: 180px; background-color: #6750A4; color: white; border-radius: 18px; border: none; font-weight: bold; cursor: pointer;'},
                  events: {'click': (e) => _createManagedProfile()}
              )
            ],
            attributes: const {'style': 'border: 1px dashed #ccc; padding: 20px; border-radius: 8px; background-color: #fcfcfc; display: flex; flex-direction: column; gap: 12px; width: 100%; box-sizing: border-box;'},
          ),
          if (_managedProfiles.isNotEmpty) ...[
            div([], attributes: const {'style': 'height: 24px;'}),
            h3([text("PROFILES CURRENTLY UNDER YOUR MANAGEMENT")], classes: 'font-bold text-xs text-gray mt-4', attributes: const {'style': 'margin-top: 0; margin-bottom: 8px;'}),
            div(
                [
                  for (var p in _managedProfiles)
                    div(
                        attributes: const {
                          'style': 'position: relative; display: flex; flex-direction: column; border: 1px solid #eee; border-radius: 6px; background-color: #f9f9f9; box-sizing: border-box; overflow: hidden;'
                        },
                        [
                          a(
                              [
                                span([text(p['displayName'] ?? '')], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black; max-width: 140px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block;'}),
                                span([text('@${p['username']}')], attributes: const {'style': 'font-size: 11px; color: #666; margin-top: 4px; max-width: 140px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block;'})
                              ],
                              href: '/${p['username']}',
                              classes: 'hover:bg-gray-100 transition-all flex-1',
                              attributes: const {
                                'style': 'display: flex; flex-direction: column; padding: 14px 12px; text-decoration: none;'
                              }
                          ),
                          button(
                              [
                                span([text('delete')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 16px;'})
                              ],
                              attributes: const {
                                'style': 'position: absolute; top: 12px; right: 12px; border: none; background: rgba(0,0,0,0.04); border-radius: 50%; width: 26px; height: 26px; display: flex; align-items: center; justify-content: center; cursor: pointer; color: #ff5252; transition: background 0.15s;'
                              },
                              events: {
                                'click': (dynamic e) {
                                  try {
                                    e.preventDefault();
                                    e.stopPropagation();
                                  } catch (_) {}
                                  setState(() {
                                    _pendingDeleteProfileId = p['id'] ?? p['uid'];
                                    _pendingDeleteProfileUsername = p['username'];
                                    _pendingDeleteProfileDisplayName = p['displayName'] ?? p['username'];
                                  });
                                }
                              }
                          )
                        ]
                    )
                ],
                attributes: const {'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; width: 100%; box-sizing: border-box;'}
            )
          ]
        ],
        classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-6',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 24px; padding: 24px; background: white; box-sizing: border-box;'}
    );
  }

  Component _buildShortcodesSettingsView() {
    return div(
        [
          h2([text("GLOBAL CONGESTION ROUTING SHORTCODES")], classes: 'font-bold text-sm text-gray mb-4', attributes: const {'style': 'margin-top: 0;'}),
          p([text("Configure the default shortcode bindings representing the Global 'Book of the Week' presented to guests on sign in or registration workflows.")], classes: 'text-xs text-gray italic leading-relaxed', attributes: const {'style': 'margin: 0;'}),
          div([], attributes: const {'style': 'height: 12px;'}),
          div(
              [
                span([text("LOGIN STICKER SHORTCODE")], classes: 'text-xs font-bold text-gray', attributes: const {'style': 'margin-bottom: 6px;'}),
                input(attributes: {'value': _loginZineShortcode, 'style': 'margin-bottom: 0; background: white;'}, events: {'input': (e) => _loginZineShortcode = getInputValue(e)})
              ],
              classes: 'flex-col gap-2',
              attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px;'}
          ),
          div(
              [
                span([text("REGISTRATION STICKER SHORTCODE")], classes: 'text-xs font-bold text-gray', attributes: const {'style': 'margin-bottom: 6px;'}),
                input(attributes: {'value': _registerZineShortcode, 'style': 'margin-bottom: 0; background: white;'}, events: {'input': (e) => _registerZineShortcode = getInputValue(e)})
              ],
              classes: 'flex-col gap-2',
              attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px;'}
          ),
          div([], attributes: const {'style': 'height: 12px;'}),
          if (_settingsFeedback != null)
            p([text(_settingsFeedback!)], attributes: {
              'style': 'font-size: 12px; font-weight: bold; margin: 4px 0; color: ${_isSettingsError ? "#ef4444" : "#16a34a"}'
            }),
          button(
              [text(_isSavingSettings ? "saving..." : "save settings")],
              classes: 'btn-primary nav-pill',
              attributes: _isSavingSettings
                  ? const {'disabled': 'true', 'style': 'height: 38px; display: inline-flex; align-items: center; justify-content: center; width: 160px;'}
                  : const {'style': 'height: 38px; display: inline-flex; align-items: center; justify-content: center; width: 160px; background-color: #6750A4; color: white; border-radius: 19px; border: none; font-weight: bold; cursor: pointer;'},
              events: {'click': (e) => _saveGlobalSettings()}
          )
        ],
        classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px; padding: 24px; background: white; box-sizing: border-box;'}
    );
  }

  Component _buildPermissionsSettingsView() {
    if (_loadingUsers) {
      return div(
        [p([text('Loading system accounts...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }
    if (_allSystemUsers.isEmpty) {
      return div(
        [p([text('No registered Users loaded.')], classes: 'text-sm text-gray italic')],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }
    return div(
        [
          h2([text("SYSTEM LEVEL ROLES & ACCESS GRANTS")], classes: 'font-bold text-sm text-gray mb-4', attributes: const {'style': 'margin-top: 0;'}),
          if (_permissionFeedback != null)
            p([text(_permissionFeedback!)], attributes: const {
              'style': 'font-size: 12px; font-weight: bold; color: #6750A4; margin-bottom: 12px;'
            }),
          for (var u in _allSystemUsers)
            _buildUserPermissionManagerRow(u)
        ],
        classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px; padding: 24px; background: white; box-sizing: border-box;'}
    );
  }

  Component _buildUserPermissionManagerRow(Map<String, dynamic> u) {
    final String uid = u['uid'] ?? u['id'] ?? '';
    final String email = u['email'] ?? 'guest';
    final String currentRole = u['role'] ?? 'user';
    final bool isUserActiveInPerm = _permissionFeedbackUid == uid;
    return div(
        [
          div(
              [
                span([text(email)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black;'}),
                span([text("UID: $uid")], attributes: const {'style': 'font-size: 10px; color: #888; font-family: monospace;'}),
                if (isUserActiveInPerm && _permissionFeedback != null)
                  span([text(_permissionFeedback!)], attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #6750A4; margin-top: 2px;'})
              ],
              classes: 'flex-col gap-1',
              attributes: const {'style': 'display: flex; flex-direction: column; gap: 4px;'}
          ),
          div(
              [
                _buildRoleBadgeSelector(uid, "admin", currentRole),
                span([], attributes: const {'style': 'display: inline-block; width: 4px;'}),
                _buildRoleBadgeSelector(uid, "moderator", currentRole),
                span([], attributes: const {'style': 'display: inline-block; width: 4px;'}),
                _buildRoleBadgeSelector(uid, "curator", currentRole),
                span([], attributes: const {'style': 'display: inline-block; width: 4px;'}),
                _buildRoleBadgeSelector(uid, "user", currentRole)
              ],
              attributes: const {'style': 'display: flex; gap: 4px; align-items: center;'}
          )
        ],
        classes: 'hover:bg-gray-50 rounded-lg p-3 transition-all',
        attributes: const {
          'style': 'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #f5f5f5; padding: 12px;'
        }
    );
  }

  Component _buildRoleBadgeSelector(String uid, String role, String activeRole) {
    final bool isSelected = activeRole == role;
    return button(
        [text(role)],
        classes: isSelected ? 'active m3-chip' : 'm3-chip',
        attributes: const {
          'style': 'height: 28px; padding: 0 10px; font-size: 10px; font-weight: bold; border-radius: 50px; cursor: pointer; border: none; text-transform: uppercase;'
        },
        events: {'click': (e) => _updateUserPermission(uid, role)}
    );
  }

  @override
  Component build(BuildContext context) {
    final bool isViewerAdmin = component.viewerAccount?.role == 'admin' || (component.viewerAccount?.roles.contains('admin') ?? false);

    final List<Component> subTabs = [];

    // 1. Shortcodes segment
    if (isViewerAdmin) {
      subTabs.add(span(
          [text("shortcodes")],
          classes: _activeSubTab == 0 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
          events: {
            'click': (e) {
              setState(() => _activeSubTab = 0);
              component.onSubTabChanged(0);
            }
          }
      ));
    }

    // 2. Managed Profiles segment
    if (component.isMe || isViewerAdmin) {
      subTabs.add(span(
          [text("managed profiles")],
          classes: _activeSubTab == 1 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
          events: {
            'click': (e) {
              setState(() => _activeSubTab = 1);
              component.onSubTabChanged(1);
            }
          }
      ));
    }

    // 3. Permissions segment
    if (isViewerAdmin) {
      subTabs.add(span(
          [text("permissions")],
          classes: _activeSubTab == 2 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
          events: {
            'click': (e) {
              setState(() => _activeSubTab = 2);
              component.onSubTabChanged(2);
            }
          }
      ));
    }

    // 4. Social Buttons segment
    if (component.isMe) {
      subTabs.add(span(
          [text("social buttons")],
          classes: _activeSubTab == 3 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer',
          events: {
            'click': (e) {
              setState(() => _activeSubTab = 3);
              component.onSubTabChanged(3);
            }
          }
      ));
    }

    final List<Component> navItems = [];
    for (int i = 0; i < subTabs.length; i++) {
      navItems.add(subTabs[i]);
      if (i < subTabs.length - 1) {
        navItems.add(span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}));
      }
    }

    return div(
      [
        if (navItems.isNotEmpty)
          div(
              navItems,
              classes: 'bg-white rounded-md p-4 shadow-sm',
              attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 4px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}
          ),

        if (_activeSubTab == 3)
          _buildSocialButtonsSettingsView()
        else if (_activeSubTab == 1)
          _buildManagedProfilesSettingsView()
        else if (_activeSubTab == 0 && isViewerAdmin)
            _buildShortcodesSettingsView()
          else if (_activeSubTab == 2 && isViewerAdmin)
              _buildPermissionsSettingsView()
            else
              div([]),

        if (_pendingDeleteProfileId != null)
          ConfirmModal(
            title: 'Delete Managed Profile?',
            message: 'Are you sure you want to delete the profile for "${_pendingDeleteProfileDisplayName}" (@${_pendingDeleteProfileUsername}) forever? This will delete their profile and release the handle.',
            confirmLabel: 'DELETE',
            isDestructive: true,
            onCancel: () {
              setState(() {
                _pendingDeleteProfileId = null;
                _pendingDeleteProfileUsername = null;
                _pendingDeleteProfileDisplayName = null;
              });
            },
            onConfirm: () {
              final id = _pendingDeleteProfileId!;
              final username = _pendingDeleteProfileUsername!;
              _deleteManagedProfile(id, username);
              setState(() {
                _pendingDeleteProfileId = null;
                _pendingDeleteProfileUsername = null;
                _pendingDeleteProfileDisplayName = null;
              });
            },
          )
      ],
    );
  }
}