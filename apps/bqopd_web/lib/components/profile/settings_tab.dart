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
    if (component.viewerAccount != null && component.viewerAccount!.preferences.containsKey('socialButtons')) {
      _socialButtonVisibility = Map<String, bool>.from(component.viewerAccount!.preferences['socialButtons']);
    }
    _loadGlobalSettings();

    // SERVER PRE-RENDERING GUARD: Defer listener setup to client only
    if (kIsWeb) {
      Future.microtask(() {
        if (mounted) {
          _listenToManagedProfiles();
          _listenToSystemUsers();
        }
      });
    }
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
    if (component.viewerAccount != null && component.viewerAccount!.preferences.containsKey('socialButtons')) {
      _socialButtonVisibility = Map<String, bool>.from(component.viewerAccount!.preferences['socialButtons']);
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

    // WIDE-OPEN QUERY: Removed 'isManaged' == true filter to fetch no matter any setting or status
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

          // Check if targetUserId is explicitly assigned as a manager of this profile
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

      // 1. Commit managed profile doc to profiles
      await fsSetDoc('profiles/$uniqueId', jsonEncode(publicData), true);

      // 2. Claim username reference
      await fsSetDoc('usernames/$baseHandle', jsonEncode({
        'uid': uniqueId,
        'isManaged': true,
        'createdAt': WebFieldValue.serverTimestamp()
      }), true);

      // 3. Register uppercase shortcode lookup (FIXES vanity path resolution inside Jaspr)
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

      print("[SETTINGS TAB] Deleting profiles/$profileDocId, usernames/$cleanUsername, shortcodes/${cleanUsername.toUpperCase()}");

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

  Future<void> _toggleSocialButtonVisibility(String toolId) async {
    final currentVal = _socialButtonVisibility[toolId] ?? true;
    final nextVal = !currentVal;
    setState(() {
      _socialButtonVisibility[toolId] = nextVal;
    });
    await fsUpdateDoc('Users/${component.targetUserId}', jsonEncode({
      'preferences.socialButtons.$toolId': nextVal
    }));
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

  Component _buildSocialButtonsSettingsView() {
    final togglableTools = ReaderToolsConfig.tools
        .where((t) => t.id != 'Settings' && t.role == ToolRole.public)
        .toList();
    return div(
        [
          h2([text("CUSTOMIZE SOCIAL TOOLBAR BUTTONS")], classes: 'font-bold text-sm text-gray mb-4', attributes: const {'style': 'margin-top: 0;'}),
          p([text("Toggle standard main social buttons on or off to custom-tailor what reader tools display on public gallery interfaces.")], classes: 'text-xs text-gray italic leading-relaxed mb-4', attributes: const {'style': 'margin: 0 0 16px 0;'}),
          for (var tool in togglableTools)
            _buildToolbarButtonSettingsRow(tool)
        ],
        classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px; padding: 24px; background: white; box-sizing: border-box;'}
    );
  }

  Component _buildToolbarButtonSettingsRow(ReaderTool tool) {
    final bool isVisible = _socialButtonVisibility[tool.id] ?? true;
    final resolvedIcon = cleanIconName(tool.defaultIcon);
    return div(
        [
          div(
            [
              span([text(resolvedIcon)], classes: 'material-symbols-outlined text-gray-500', attributes: const {'style': 'font-size: 22px;'}),
              span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
              span([text(tool.label)], attributes: const {'style': 'font-size: 14px; font-weight: bold; color: black;'})
            ],
            attributes: const {'style': 'display: flex; align-items: center;'},
          ),
          div(
              [
                div(
                    [],
                    attributes: {
                      'style': 'width: 20px; height: 20px; border-radius: 50%; background-color: white; transition: left 0.25s; position: absolute; '
                          'left: ${isVisible ? '22px' : '2px'}; top: 2px;'
                    }
                )
              ],
              attributes: {
                'style': 'width: 44px; height: 24px; border-radius: 100px; padding: 2px; position: relative; transition: background 0.25s; cursor: pointer; box-sizing: border-box; '
                    'background-color: ${isVisible ? '#6750A4' : '#ccc'};'
              }
          )
        ],
        classes: 'hover:bg-gray-50 rounded-lg p-3 transition-all',
        attributes: const {
          'style': 'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #f5f5f5; cursor: pointer; padding: 12px;'
        },
        events: {
          'click': (e) => _toggleSocialButtonVisibility(tool.id)
        }
    );
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
                          // Clickable link part
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
                          // Absolute positioned Delete Button on the card
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

    // Build sub-tab segments list in the exact requested order
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

    // 4. Social Buttons segment (renamed from "toolbar buttons")
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

    // Assemble tabs with dividers elegantly
    final List<Component> navItems = [];
    for (int i = 0; i < subTabs.length; i++) {
      navItems.add(subTabs[i]);
      if (i < subTabs.length - 1) {
        navItems.add(span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}));
      }
    }

    return div(
      [
        // Dynamic, divider-aware navigation segment row
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

        // Layered Delete Confirmation Modal
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