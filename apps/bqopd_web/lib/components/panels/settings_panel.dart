import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/icon_utils.dart';

class SettingsPanel extends StatefulComponent {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
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
    if (_loading) return div(classes: 'p-4 text-center', [text('Loading preferences...')]);
    if (_uid == null) {
      return div(classes: 'p-6 text-center flex flex-col justify-center items-center gap-2', [
        p(classes: 'text-gray text-sm', [text('Please sign in to customize your toolbar.')]),
        button(
            classes: 'btn-primary mt-2',
            events: {'click': (e) => GlobalModalBus.show()},
            [text('Sign In')]
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
            span(classes: 'material-symbols-outlined text-gray-500', [text(resolvedIcon)]),
            span(classes: 'text-sm font-medium', [text(tool.label)]),
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