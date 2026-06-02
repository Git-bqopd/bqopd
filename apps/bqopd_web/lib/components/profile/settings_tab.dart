import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../utils/icon_utils.dart';

/// Customizable toolbar configurations, managed profiles form, global default shortcodes, and administrator role parameters.
class SettingsTab extends StatefulComponent {
  final UserAccount? viewerAccount;
  final String targetUserId;
  final bool isMe;
  final List<Map<String, dynamic>> allManagedProfiles;
  final List<Map<String, dynamic>> allSystemUsers;
  final int initialSubTab;
  final void Function(int) onSubTabChanged;

  const SettingsTab({
    required this.viewerAccount,
    required this.targetUserId,
    required this.isMe,
    required this.allManagedProfiles,
    required this.allSystemUsers,
    required this.initialSubTab,
    required this.onSubTabChanged,
    super.key,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  int _activeSubTab = 0;
  Map<String, bool> _socialButtonVisibility = {};

  // Create Managed Profile Inputs
  String _newManagedFirstName = '';
  String _newManagedLastName = '';
  String _newManagedBio = '';
  bool _isCreatingManagedProfile = false;

  // Global shortcode configurations
  String _loginZineShortcode = '';
  String _registerZineShortcode = '';
  bool _isSavingSettings = false;

  @override
  void initState() {
    super.initState();
    _activeSubTab = component.initialSubTab;
    if (component.viewerAccount != null && component.viewerAccount!.preferences.containsKey('socialButtons')) {
      _socialButtonVisibility = Map<String, bool>.from(component.viewerAccount!.preferences['socialButtons']);
    }
    _loadGlobalSettings();
  }

  @override
  void didUpdateComponent(SettingsTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialSubTab != component.initialSubTab) {
      _activeSubTab = component.initialSubTab;
    }
    if (component.viewerAccount != null && component.viewerAccount!.preferences.containsKey('socialButtons')) {
      _socialButtonVisibility = Map<String, bool>.from(component.viewerAccount!.preferences['socialButtons']);
    }
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

  Future<void> _saveGlobalSettings() async {
    setState(() => _isSavingSettings = true);
    try {
      await fsSetDoc('app_settings/main_settings', jsonEncode({
        'login_zine_shortcode': _loginZineShortcode.trim(),
        'register_zine_shortcode': _registerZineShortcode.trim()
      }), true);
    } catch (e) {
      print("Error saving global settings: $e");
    }
    setState(() => _isSavingSettings = false);
  }

  Future<void> _createManagedProfile() async {
    if (_newManagedFirstName.trim().isEmpty || _newManagedLastName.trim().isEmpty) return;
    setState(() => _isCreatingManagedProfile = true);
    try {
      final String baseHandle = "${_newManagedFirstName.trim()}-${_newManagedLastName.trim()}"
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9-]'), '-');
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
      setState(() {
        _newManagedFirstName = '';
        _newManagedLastName = '';
        _newManagedBio = '';
        _isCreatingManagedProfile = false;
      });
    } catch (e) {
      print("Error creating managed profile: $e");
      setState(() => _isCreatingManagedProfile = false);
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
    final bool isCurator = newRole == 'curator' || newRole == 'admin' || newRole == 'moderator';
    await fsUpdateDoc('Users/$uid', jsonEncode({
      'role': newRole,
      'isCurator': isCurator
    }));
    await fsUpdateDoc('profiles/$uid', jsonEncode({
      'isCurator': isCurator,
      'isAdmin': newRole == 'admin'
    }));
  }

  Component _buildSocialButtonsSettingsView() {
    final togglableTools = ReaderToolsConfig.tools
        .where((t) => t.id != 'Settings' && t.role == ToolRole.public)
        .toList();
    return div([
      h2([text("CUSTOMIZE SOCIAL TOOLBAR BUTTONS")], classes: 'font-bold text-sm text-gray mb-4'),
      for (var tool in togglableTools)
        _buildToolbarButtonSettingsRow(tool)
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  Component _buildToolbarButtonSettingsRow(ReaderTool tool) {
    final bool isVisible = _socialButtonVisibility[tool.id] ?? true;
    final resolvedIcon = cleanIconName(tool.defaultIcon);
    return div([
      div([
        span([text(resolvedIcon)], classes: 'material-symbols-outlined text-gray-500', attributes: const {'style': 'font-size: 22px;'}),
        span([], attributes: const {'style': 'display: inline-block; width: 16px;'}),
        span([text(tool.label)], attributes: const {'style': 'font-size: 14px; font-weight: bold; color: black;'})
      ], attributes: const {'style': 'display: flex; align-items: center;'}),
      div([
        div([], attributes: {
          'style': 'width: 20px; height: 20px; border-radius: 50%; background-color: white; transition: left 0.25s; position: absolute; '
              'left: ${isVisible ? '22px' : '2px'};'
        })
      ], attributes: {
        'style': 'width: 44px; height: 24px; border-radius: 100px; padding: 2px; position: relative; transition: background 0.25s; cursor: pointer; '
            'background-color: ${isVisible ? '#6750A4' : '#ccc'};'
      })
    ], classes: 'hover:bg-gray-50 rounded-lg p-3 transition-all', attributes: const {
      'style': 'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #f5f5f5; cursor: pointer;'
    }, events: {
      'click': (e) => _toggleSocialButtonVisibility(tool.id)
    });
  }

  Component _buildManagedProfilesSettingsView() {
    return div([
      div([
        h3([text("Create Managed Identity (Human or Estate)")], classes: 'font-bold text-sm text-black'),
        div([
          input(attributes: {'placeholder': 'First Name', 'value': _newManagedFirstName}, events: {'input': (e) => _newManagedFirstName = getInputValue(e)}),
          span([], attributes: const {'style': 'display: inline-block; width: 12px;'}),
          input(attributes: {'placeholder': 'Last Name', 'value': _newManagedLastName}, events: {'input': (e) => _newManagedLastName = getInputValue(e)}),
        ], attributes: const {'style': 'display: flex; gap: 12px;'}),
        input(attributes: {'placeholder': 'Identity Biography / Historical Context', 'value': _newManagedBio}, events: {'input': (e) => _newManagedBio = getInputValue(e)}),
        button(
            [text(_isCreatingManagedProfile ? "initializing..." : "create profile")],
            classes: 'btn-primary nav-pill',
            attributes: _isCreatingManagedProfile
                ? const {'disabled': 'true', 'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; width: 180px;'}
                : const {'style': 'height: 36px; display: inline-flex; align-items: center; justify-content: center; width: 180px;'},
            events: {'click': (e) => _createManagedProfile()}
        )
      ], attributes: const {'style': 'border: 1px dashed #ccc; padding: 20px; border-radius: 8px; background-color: #fcfcfc; display: flex; flex-direction: column; gap: 12px;'}),

      if (component.allManagedProfiles.isNotEmpty) ...[
        div([], attributes: const {'style': 'height: 24px;'}),
        h3([text("PROFILES CURRENTLY UNDER YOUR MANAGEMENT")], classes: 'font-bold text-xs text-gray mt-4'),
        div([], attributes: const {'style': 'height: 8px;'}),
        div([
          for (var p in component.allManagedProfiles)
            a([
              span([text(p['displayName'] ?? '')], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black;'}),
              span([text('@${p['username']}')], attributes: const {'style': 'font-size: 11px; color: #666; margin-top: 4px;'})
            ], href: '/${p['username']}', classes: 'bg-gray-50 hover:bg-gray-100 rounded-md p-4 transition-all', attributes: const {'style': 'display: flex; flex-direction: column; border: 1px solid #eee; cursor: pointer;'})
        ], attributes: const {'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px;'})
      ]
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-6');
  }

  Component _buildShortcodesSettingsView() {
    return div([
      h2([text("GLOBAL CONGESTION ROUTING SHORTCODES")], classes: 'font-bold text-sm text-gray mb-4'),
      p([text("Configure the default shortcode bindings representing the Global 'Book of the Week' presented to guests on sign in or registration workflows.")], classes: 'text-xs text-gray italic leading-relaxed'),
      div([], attributes: const {'style': 'height: 12px;'}),
      div([
        span([text("LOGIN STICKER SHORTCODE")], classes: 'text-xs font-bold text-gray'),
        input(attributes: {'value': _loginZineShortcode}, events: {'input': (e) => _loginZineShortcode = getInputValue(e)})
      ], classes: 'flex-col gap-2'),
      div([
        span([text("REGISTRATION STICKER SHORTCODE")], classes: 'text-xs font-bold text-gray'),
        input(attributes: {'value': _registerZineShortcode}, events: {'input': (e) => _registerZineShortcode = getInputValue(e)})
      ], classes: 'flex-col gap-2'),
      div([], attributes: const {'style': 'height: 12px;'}),
      button(
          [text(_isSavingSettings ? "saving..." : "save settings")],
          classes: 'btn-primary nav-pill',
          attributes: _isSavingSettings
              ? const {'disabled': 'true', 'style': 'height: 38px; display: inline-flex; align-items: center; justify-content: center; width: 160px;'}
              : const {'style': 'height: 38px; display: inline-flex; align-items: center; justify-content: center; width: 160px;'},
          events: {'click': (e) => _saveGlobalSettings()}
      )
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  Component _buildPermissionsSettingsView() {
    if (component.allSystemUsers.isEmpty) {
      return div([
        p([text('No registered Users loaded.')], classes: 'text-sm text-gray italic')
      ], classes: 'bg-white rounded-lg p-16 shadow-sm text-center');
    }
    return div([
      h2([text("SYSTEM LEVEL ROLES & ACCESS GRANTS")], classes: 'font-bold text-sm text-gray mb-4'),
      for (var u in component.allSystemUsers)
        _buildUserPermissionManagerRow(u)
    ], classes: 'bg-white rounded-lg p-6 shadow-sm flex-col gap-4');
  }

  Component _buildUserPermissionManagerRow(Map<String, dynamic> u) {
    final String uid = u['uid'] ?? u['id'] ?? '';
    final String email = u['email'] ?? 'guest';
    final String currentRole = u['role'] ?? 'user';
    return div([
      div([
        span([text(email)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: black;'}),
        span([text("UID: $uid")], attributes: const {'style': 'font-size: 10px; color: #888; font-family: monospace;'})
      ], classes: 'flex-col gap-1'),
      div([
        _buildRoleBadgeSelector(uid, "admin", currentRole),
        span([], attributes: const {'style': 'display: inline-block; width: 8px;'}),
        _buildRoleBadgeSelector(uid, "moderator", currentRole),
        span([], attributes: const {'style': 'display: inline-block; width: 8px;'}),
        _buildRoleBadgeSelector(uid, "curator", currentRole),
        span([], attributes: const {'style': 'display: inline-block; width: 8px;'}),
        _buildRoleBadgeSelector(uid, "user", currentRole)
      ], attributes: const {'style': 'display: flex; gap: 8px;'})
    ], classes: 'hover:bg-gray-50 rounded-lg p-3 transition-all', attributes: const {
      'style': 'display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #f5f5f5;'
    });
  }

  Component _buildRoleBadgeSelector(String uid, String role, String activeRole) {
    final bool isSelected = activeRole == role;
    return button(
        [text(role)],
        classes: isSelected ? 'active m3-chip' : 'm3-chip',
        attributes: const {'style': 'height: 28px; padding: 0 10px; font-size: 10px; font-weight: bold; border-radius: 50px; cursor: pointer; border: none; text-transform: uppercase;'},
        events: {'click': (e) => _updateUserPermission(uid, role)}
    );
  }

  @override
  Component build(BuildContext context) {
    final bool isViewerAdmin = component.viewerAccount?.role == 'admin' || (component.viewerAccount?.roles.contains('admin') ?? false);

    return div([
      div([
        span([text("toolbar buttons")], classes: _activeSubTab == 3 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
          'click': (e) {
            setState(() => _activeSubTab = 3);
            component.onSubTabChanged(3);
          }
        }),
        span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
        span([text("managed profiles")], classes: _activeSubTab == 1 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
          'click': (e) {
            setState(() => _activeSubTab = 1);
            component.onSubTabChanged(1);
          }
        }),
        if (isViewerAdmin) ...[
          span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
          span([text("shortcodes")], classes: _activeSubTab == 0 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
            'click': (e) {
              setState(() => _activeSubTab = 0);
              component.onSubTabChanged(0);
            }
          }),
          span([text('|')], classes: 'text-xs text-gray', attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
          span([text("permissions")], classes: _activeSubTab == 2 ? 'text-xs font-bold text-black border-b border-black cursor-pointer' : 'text-xs text-gray cursor-pointer', events: {
            'click': (e) {
              setState(() => _activeSubTab = 2);
              component.onSubTabChanged(2);
            }
          }),
        ]
      ], classes: 'bg-white rounded-md p-4 shadow-sm', attributes: const {'style': 'display: flex; flex-wrap: wrap; justify-content: center; align-items: center; gap: 8px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'}),

      if (_activeSubTab == 3)
        _buildSocialButtonsSettingsView()
      else if (_activeSubTab == 1)
        _buildManagedProfilesSettingsView()
      else if (_activeSubTab == 0 && isViewerAdmin)
          _buildShortcodesSettingsView()
        else if (_activeSubTab == 2 && isViewerAdmin)
            _buildPermissionsSettingsView()
          else
            div([])
    ]);
  }
}