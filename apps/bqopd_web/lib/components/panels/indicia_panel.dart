import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';

/// Indicia Panel containing fanzine publisher details and copyright metadata.
/// Supports inline rich text updates in editing mode.
class IndiciaPanel extends StatefulComponent {
  final String fanzineId;
  final bool isEditingMode;

  const IndiciaPanel({required this.fanzineId, required this.isEditingMode, super.key});

  @override
  State<IndiciaPanel> createState() => _IndiciaPanelState();
}

class _IndiciaPanelState extends State<IndiciaPanel> {
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
  void didUpdateComponent(IndiciaPanel oldComponent) {
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
        p([text(_indiciaText)], attributes: const {
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
            },
            events: {
              'input': (e) => setState(() => _indiciaText = getInputValue(e))
            },
            [text(_indiciaText)]
        )
      ]),
      div(classes: 'flex flex-row justify-between items-center mt-3', [
        span([
          text(_statusMessage)
        ], classes: _isError ? 'text-xs text-red-500 font-bold' : 'text-xs text-green-600 font-bold'),
        button(
            classes: 'btn-primary nav-pill mb-0',
            attributes: {
              'style': 'padding: 8px 16px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
              if (_saving) 'disabled': 'true'
            },
            events: {'click': (e) => _save()},
            [text(_saving ? 'Saving...' : 'Save Indicia')]
        )
      ])
    ]);
  }
}