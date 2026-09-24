import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/icon_utils.dart';

/// Dedicated inline drawer (bonusRow) view for toolbar button customization.
class SettingsRowPanel extends StatefulComponent {
  const SettingsRowPanel({super.key});

  @override
  State<SettingsRowPanel> createState() => _SettingsRowPanelState();
}

class _SettingsRowPanelState extends State<SettingsRowPanel> {
  Map<String, bool> _visibility = {};
  bool _loading = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadPreferences();
    }
  }

  Future<void> _loadPreferences() async {
    final uid = getCurrentUserId();
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await fsGetDoc('Users/$uid');
      final doc = jsonDecode(res);
      if (doc['exists'] && mounted) {
        final data = doc['data'] as Map<String, dynamic>;
        final prefs = data['preferences'] as Map<String, dynamic>? ?? {};
        final buttons = prefs['socialButtons'] as Map<String, dynamic>? ?? {};
        setState(() {
          _uid = uid;
          _visibility = Map<String, bool>.from(buttons);
          _loading = false;
        });
      }
    } catch (e) {
      print("Error loading settings: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String toolId) async {
    if (_uid == null) return;
    final current = _visibility[toolId] ?? true;
    final next = !current;
    setState(() {
      _visibility[toolId] = next;
    });
    await fsUpdateDoc('Users/$_uid', jsonEncode({
      'preferences.socialButtons.$toolId': next
    }));
  }

  @override
  Component build(BuildContext context) {
    if (_loading) return div(classes: 'p-4 text-center', [Component.text('Loading preferences...')]);
    if (_uid == null) {
      return div(classes: 'p-6 text-center flex flex-col justify-center items-center gap-2', [
        p(classes: 'text-gray text-sm', [Component.text('Please sign in to customize your toolbar.')]),
        button(
            classes: 'btn-primary mt-2',
            events: {'click': (e) => GlobalModalBus.show()},
            [Component.text('Sign In')]
        )
      ]);
    }

    final togglableTools = ReaderToolsConfig.tools
        .where((t) => t.id != 'Settings' && t.scopes.contains(ToolScope.reader))
        .toList();

    return div(classes: 'flex-col gap-2 py-4', [
      for (var tool in togglableTools)
        _buildToggleRow(tool)
    ]);
  }

  Component _buildToggleRow(ReaderTool tool) {
    final bool isVisible = _visibility[tool.id] ?? true;
    final resolvedIcon = cleanIconName(tool.defaultIcon);

    return div(
        classes: 'flex-row items-center justify-between p-3 border-b border-gray-50 hover:bg-gray-50 cursor-pointer transition-colors',
        events: {'click': (e) => _toggle(tool.id)},
        [
          div(classes: 'flex-row items-center gap-3', [
            span(classes: 'material-symbols-outlined text-gray-500', [Component.text(resolvedIcon)]),
            span(classes: 'text-sm font-medium', [Component.text(tool.label)]),
          ]),
          div(
              classes: 'w-10 h-6 rounded-full relative transition-colors ${isVisible ? 'bg-indigo-600' : 'bg-gray-300'}',
              [
                div(
                    classes: 'absolute top-1 w-4 h-4 bg-white rounded-full transition-all ${isVisible ? 'left-5' : 'left-1'}',
                    []
                )
              ]
          )
        ]
    );
  }
}

/// Dedicated desktop 3rd column (bonusColumn) single-window view for toolbar configuration.
class SettingsColumnPanel extends StatefulComponent {
  const SettingsColumnPanel({super.key});

  @override
  State<SettingsColumnPanel> createState() => _SettingsColumnPanelState();
}

class _SettingsColumnPanelState extends State<SettingsColumnPanel> {
  Map<String, bool> _visibility = {};
  bool _loading = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadPreferences();
    }
  }

  Future<void> _loadPreferences() async {
    final uid = getCurrentUserId();
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await fsGetDoc('Users/$uid');
      final doc = jsonDecode(res);
      if (doc['exists'] && mounted) {
        final data = doc['data'] as Map<String, dynamic>;
        final prefs = data['preferences'] as Map<String, dynamic>? ?? {};
        final buttons = prefs['socialButtons'] as Map<String, dynamic>? ?? {};
        setState(() {
          _uid = uid;
          _visibility = Map<String, bool>.from(buttons);
          _loading = false;
        });
      }
    } catch (e) {
      print("Error loading settings: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String toolId) async {
    if (_uid == null) return;
    final current = _visibility[toolId] ?? true;
    final next = !current;
    setState(() {
      _visibility[toolId] = next;
    });
    await fsUpdateDoc('Users/$_uid', jsonEncode({
      'preferences.socialButtons.$toolId': next
    }));
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'p-6 text-center text-gray italic text-xs', [Component.text('Loading preferences...')]);
    }
    if (_uid == null) {
      return div(
        classes: 'p-8 text-center flex-col items-center justify-center gap-3',
        attributes: const {
          'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 32px; background: white; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.05);'
        },
        [
          span([Component.text('tune')], classes: 'material-symbols-outlined text-gray-400', attributes: const {'style': 'font-size: 40px;'}),
          p([Component.text('Sign in to customize your toolbar buttons.')], classes: 'text-sm text-gray font-medium'),
          button(
              classes: 'btn-primary nav-pill mt-2',
              attributes: const {
                'style': 'padding: 8px 20px; font-size: 12px; background-color: #6750A4; color: white; border: none; border-radius: 50px; cursor: pointer;'
              },
              events: {'click': (e) => GlobalModalBus.show()},
              [Component.text('Sign In')]
          )
        ],
      );
    }

    final togglableTools = ReaderToolsConfig.tools
        .where((t) => t.id != 'Settings' && t.scopes.contains(ToolScope.reader))
        .toList();

    return div(
      [
        div(
            [
              div([
                span([Component.text('CUSTOMIZE TOOLBAR BUTTONS')], attributes: const {
                  'style': 'font-size: 11px; font-weight: bold; color: #475569; letter-spacing: 0.5px; text-transform: uppercase;'
                }),
                span([Component.text('Toggle buttons shown in your reading toolbar.')], attributes: const {
                  'style': 'font-size: 10px; color: #94a3b8; display: block; margin-top: 2px;'
                }),
              ]),
            ],
            attributes: const {'style': 'margin-bottom: 16px; width: 100%;'}
        ),
        div(
            [
              for (var tool in togglableTools)
                _buildColumnToggleItem(tool),
            ],
            classes: 'flex-col gap-2',
            attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'}
        )
      ],
      classes: 'bg-white rounded-lg border border-gray-300 shadow-md p-5',
      attributes: const {
        'style': 'background-color: #ffffff; border: 1px solid #cbd5e1; border-radius: 8px; padding: 20px; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08); width: 100%; box-sizing: border-box;'
      },
    );
  }

  Component _buildColumnToggleItem(ReaderTool tool) {
    final bool isVisible = _visibility[tool.id] ?? true;
    final resolvedIcon = cleanIconName(tool.defaultIcon);

    return div(
        classes: 'hover:bg-gray-50 transition-colors',
        attributes: const {
          'style': 'display: flex; flex-direction: row; align-items: center; justify-content: space-between; padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 8px; cursor: pointer; background: white;'
        },
        events: {'click': (e) => _toggle(tool.id)},
        [
          div(
              [
                span([Component.text(resolvedIcon)], classes: 'material-symbols-outlined text-gray-500', attributes: const {'style': 'font-size: 20px;'}),
                div(
                    [
                      span([Component.text(tool.label)], attributes: const {'style': 'font-size: 13px; font-weight: bold; color: #1e293b;'}),
                      span([Component.text(tool.description)], attributes: const {'style': 'font-size: 11px; color: #64748b; margin-top: 2px; line-height: 1.3;'}),
                    ],
                    attributes: const {'style': 'display: flex; flex-direction: column; gap: 1px;'}
                )
              ],
              attributes: const {'style': 'display: flex; align-items: center; gap: 12px;'}
          ),
          div(
              [
                div(
                    [],
                    attributes: {
                      'style': 'position: absolute; top: 2px; width: 16px; height: 16px; background-color: white; border-radius: 50%; transition: left 0.2s; box-shadow: 0 1px 2px rgba(0,0,0,0.2); left: ${isVisible ? "22px" : "2px"};'
                    }
                )
              ],
              attributes: {
                'style': 'width: 40px; height: 20px; border-radius: 20px; position: relative; transition: background-color 0.2s; background-color: ${isVisible ? "#6750A4" : "#cbd5e1"}; flex-shrink: 0;'
              }
          )
        ]
    );
  }
}

/// Backwards-compatible alias for the default row panel
typedef SettingsPanel = SettingsRowPanel;