import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_utils.dart';

/// Dedicated inline drawer (bonusRow) view for issue indicia and copyright.
class IndiciaRowPanel extends StatefulComponent {
  final String fanzineId;
  const IndiciaRowPanel({required this.fanzineId, super.key});

  @override
  State<IndiciaRowPanel> createState() => _IndiciaRowPanelState();
}

class _IndiciaRowPanelState extends State<IndiciaRowPanel> {
  String _indiciaText = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateComponent(IndiciaRowPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.fanzineId != component.fanzineId) {
      _load();
    }
  }

  Future<void> _load() async {
    if (component.fanzineId.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await fsGetDoc('fanzines/${component.fanzineId}');
      final doc = jsonDecode(res);
      if (doc['exists'] == true) {
        setState(() {
          _indiciaText = doc['data']['masterIndicia'] ?? '© 2026 BQOPD Collective.';
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'skeleton-line shimmer-bg', []);
    }
    return div([
      p([Component.text(_indiciaText)], attributes: const {
        'style': "font-family: Georgia, serif; font-size: 13px; line-height: 1.6; text-align: justify; color: #333; white-space: pre-wrap;"
      })
    ]);
  }
}

/// Dedicated desktop 3rd column (bonusColumn) view for publication indicia.
/// Supports inline rich text editing for editor and curator workspaces.
class IndiciaColumnPanel extends StatefulComponent {
  final String fanzineId;
  final bool isEditingMode;

  const IndiciaColumnPanel({
    required this.fanzineId,
    this.isEditingMode = true,
    super.key,
  });

  @override
  State<IndiciaColumnPanel> createState() => _IndiciaColumnPanelState();
}

class _IndiciaColumnPanelState extends State<IndiciaColumnPanel> {
  String _indiciaText = '';
  bool _loading = true;
  bool _saving = false;
  String _statusMessage = '';
  bool _isError = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateComponent(IndiciaColumnPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.fanzineId != component.fanzineId) {
      _load();
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (component.fanzineId.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await fsGetDoc('fanzines/${component.fanzineId}');
      final doc = jsonDecode(res);
      if (doc['exists'] == true) {
        setState(() {
          _indiciaText = doc['data']['masterIndicia'] ?? '© 2026 BQOPD Collective.';
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _statusMessage = 'Saving indicia...';
      _isError = false;
    });
    try {
      await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode({
        'masterIndicia': _indiciaText.trim(),
      }));
      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Indicia saved successfully!';
          _isError = false;
        });
        _resetStatusTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Failed to save: $e';
          _isError = true;
        });
      }
    }
  }

  void _resetStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _statusMessage = '';
        });
      }
    });
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'skeleton-line shimmer-bg', []);
    }
    if (!component.isEditingMode) {
      return div([
        p([Component.text(_indiciaText)], attributes: const {
          'style': "font-family: Georgia, serif; font-size: 13px; line-height: 1.6; text-align: justify; color: #333; white-space: pre-wrap;"
        })
      ]);
    }
    return div(classes: 'flex-col text-left', [
      div(classes: 'grow-wrap', attributes: {'data-replicated-value': _indiciaText}, [
        textarea(
            classes: 'border border-gray-300 rounded-md',
            attributes: {
              'placeholder': 'Enter master publication indicia or copyright details...',
              'oninput': 'this.parentNode.dataset.replicatedValue = this.value',
              'style': 'min-height: 120px;',
            },
            events: {
              'input': (e) => setState(() => _indiciaText = getInputValue(e))
            },
            [Component.text(_indiciaText)]
        )
      ]),
      div(classes: 'flex flex-row justify-between items-center mt-3', [
        span([
          Component.text(_statusMessage)
        ], classes: _isError ? 'text-xs text-red-500 font-bold' : 'text-xs text-green-600 font-bold'),
        button(
            classes: 'btn-primary nav-pill mb-0',
            attributes: {
              'style': 'padding: 8px 18px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
              if (_saving) 'disabled': 'true'
            },
            events: {'click': (e) => _save()},
            [Component.text(_saving ? 'Saving...' : 'Save Indicia')]
        )
      ])
    ]);
  }
}

/// Backwards-compatible alias for the default row panel
class IndiciaPanel extends StatelessComponent {
  final String fanzineId;
  final bool isEditingMode;
  const IndiciaPanel({required this.fanzineId, this.isEditingMode = false, super.key});

  @override
  Component build(BuildContext context) {
    if (isEditingMode) {
      return IndiciaColumnPanel(fanzineId: fanzineId, isEditingMode: true);
    }
    return IndiciaRowPanel(fanzineId: fanzineId);
  }
}