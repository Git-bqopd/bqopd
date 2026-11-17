import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';

/// Returns all toolbar tools available for [scope] (excluding the `buttons` toggle itself).
List<ReaderTool> _toolsForScope(ToolScope scope, String? fanzineType) {
  return ReaderToolsConfig.tools.where((t) {
    if (t.id == 'Settings') return false;
    if (!t.scopes.contains(scope)) return false;
    if (t.condition == ToolCondition.requiresOcrPipeline &&
        (fanzineType == 'folio' || fanzineType == 'calendar')) {
      return false;
    }
    return true;
  }).toList();
}

/// Resolves the secondary muted label suffix shown next to a button name
/// (e.g., `(cannot be hidden)` for locked tools, `(only on some pages)` for
/// page-level conditional tools added in editor/curator scopes).
String? _disclaimerForTool(ReaderTool tool, {required bool isLocked}) {
  if (isLocked) {
    return '(cannot be hidden)';
  }
  return ReaderToolsConfig.getConditionDisclaimer(tool);
}

/// Dedicated inline drawer (bonusRow) view for toolbar button customization.
class SettingsRowPanel extends StatefulComponent {
  final ToolScope activeScope;
  final String? fanzineType;

  const SettingsRowPanel({
    this.activeScope = ToolScope.reader,
    this.fanzineType,
    super.key,
  });

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
    if (_uid == null || toolId == 'Grid' || toolId == 'Like') return;
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

    final scopeTools = _toolsForScope(component.activeScope, component.fanzineType);

    return div(classes: 'flex-col gap-2 py-4', [
      for (var tool in scopeTools)
        _buildToggleRow(tool)
    ]);
  }

  Component _buildToggleRow(ReaderTool tool) {
    final bool isLocked = tool.id == 'Grid' || tool.id == 'Like';
    final bool isVisible = isLocked ? true : (_visibility[tool.id] ?? true);
    final String? disclaimer = _disclaimerForTool(tool, isLocked: isLocked);

    return div(
      classes: 'flex-row items-center justify-between p-3 border-b border-gray-50 ${isLocked ? "" : "hover:bg-gray-50 cursor-pointer"} transition-colors',
      attributes: {
        if (isLocked) 'style': 'cursor: not-allowed;',
      },
      events: {
        if (!isLocked) 'click': (e) => _toggle(tool.id),
      },
      [
        div(
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 2px; padding-right: 12px;'},
          [
            div(
              attributes: const {'style': 'display: flex; align-items: baseline; gap: 6px; flex-wrap: wrap;'},
              [
                span(
                  attributes: const {'style': 'font-size: 13px; font-weight: bold; color: #1e293b;'},
                  [Component.text(tool.label)],
                ),
                if (disclaimer != null)
                  span(
                    attributes: const {'style': 'font-size: 11px; color: #94a3b8; font-weight: normal;'},
                    [Component.text(disclaimer)],
                  ),
              ],
            ),
            span(
              attributes: const {'style': 'font-size: 11px; color: #64748b; line-height: 1.3;'},
              [Component.text(tool.description)],
            ),
          ],
        ),
        _buildSvgSwitch(tool: tool, isVisible: isVisible, isLocked: isLocked),
      ],
    );
  }
}

/// Renders a pill switch with the button's `.svg` centered inside the sliding circular thumb.
Component _buildSvgSwitch({
  required ReaderTool tool,
  required bool isVisible,
  required bool isLocked,
}) {
  final String trackColor = isLocked
      ? 'rgba(103, 80, 164, 0.55)'
      : (isVisible ? '#6750A4' : '#cbd5e1');

  return div(
    attributes: {
      'style':
      'width: 52px; height: 28px; border-radius: 28px; position: relative; '
          'transition: background-color 0.2s; background-color: $trackColor; '
          'flex-shrink: 0; ${isLocked ? "cursor: not-allowed;" : "cursor: pointer;"}',
    },
    [
      div(
        attributes: {
          'style':
          'position: absolute; top: 3px; width: 22px; height: 22px; '
              'background-color: #ffffff; border-radius: 50%; transition: left 0.2s; '
              'box-shadow: 0 1px 3px rgba(0, 0, 0, 0.25); display: flex; '
              'align-items: center; justify-content: center; '
              'left: ${isVisible ? "27px" : "3px"};',
        },
        [
          img(
            src: tool.defaultIcon,
            attributes: {
              'alt': tool.label,
              'style':
              'width: 14px; height: 14px; object-fit: contain; display: block; '
                  'opacity: ${isVisible ? "1.0" : "0.45"};',
            },
          ),
        ],
      ),
    ],
  );
}

/// Dedicated desktop 3rd column (bonusColumn) single-window view for toolbar configuration.
class SettingsColumnPanel extends StatefulComponent {
  final ToolScope activeScope;
  final String? fanzineType;

  const SettingsColumnPanel({
    this.activeScope = ToolScope.reader,
    this.fanzineType,
    super.key,
  });

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
    if (_uid == null || toolId == 'Grid' || toolId == 'Like') return;
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

    final scopeTools = _toolsForScope(component.activeScope, component.fanzineType);

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
              for (var tool in scopeTools)
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
    final bool isLocked = tool.id == 'Grid' || tool.id == 'Like';
    final bool isVisible = isLocked ? true : (_visibility[tool.id] ?? true);
    final String? disclaimer = _disclaimerForTool(tool, isLocked: isLocked);

    return div(
      classes: isLocked ? 'transition-colors' : 'hover:bg-gray-50 transition-colors',
      attributes: {
        'style':
        'display: flex; flex-direction: row; align-items: center; justify-content: space-between; '
            'gap: 12px; padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 8px; '
            'background: ${isLocked ? "#f8fafc" : "#ffffff"}; '
            '${isLocked ? "cursor: not-allowed;" : "cursor: pointer;"}',
      },
      events: {
        if (!isLocked) 'click': (e) => _toggle(tool.id),
      },
      [
        div(
          attributes: const {'style': 'display: flex; flex-direction: column; gap: 2px; min-width: 0;'},
          [
            div(
              attributes: const {'style': 'display: flex; align-items: baseline; gap: 6px; flex-wrap: wrap;'},
              [
                span(
                  attributes: const {'style': 'font-size: 13px; font-weight: bold; color: #1e293b;'},
                  [Component.text(tool.label)],
                ),
                if (disclaimer != null)
                  span(
                    attributes: const {'style': 'font-size: 11px; font-weight: normal; color: #94a3b8;'},
                    [Component.text(disclaimer)],
                  ),
              ],
            ),
            span(
              attributes: const {'style': 'font-size: 11px; color: #64748b; margin-top: 2px; line-height: 1.3;'},
              [Component.text(tool.description)],
            ),
          ],
        ),
        _buildSvgSwitch(tool: tool, isVisible: isVisible, isLocked: isLocked),
      ],
    );
  }
}

/// Backwards-compatible alias for the default row panel
typedef SettingsPanel = SettingsRowPanel;