import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';

/// Credits Panel displaying standard list of authors and contributors for the issue page.
/// Supports addition and removal of linked creator profiles.
class CreditsPanel extends StatefulComponent {
  final String imageId;
  const CreditsPanel({required this.imageId, super.key});

  @override
  State<CreditsPanel> createState() => _CreditsPanelState();
}

class _CreditsPanelState extends State<CreditsPanel> {
  List<Map<String, dynamic>> _creators = [];
  bool _loading = true;
  bool _saving = false;
  String _statusMessage = '';
  bool _isError = false;
  Timer? _statusTimer;

  String _newHandle = '';
  String _newRole = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateComponent(CreditsPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _load();
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (component.imageId.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] == true) {
        final d = doc['data'] as Map<String, dynamic>;
        setState(() {
          _creators = (d['creators'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _statusMessage = 'Saving creators...';
      _isError = false;
    });
    try {
      await fsUpdateDoc('images/${component.imageId}', jsonEncode({
        'creators': _creators,
      }));
      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Creators saved!';
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

  Future<void> _addCreator() async {
    final handle = _newHandle.trim();
    final role = _newRole.trim();
    if (handle.isEmpty) return;

    final cleanHandle = handle.toLowerCase().replaceAll('@', '');
    String resolvedName = handle;
    String? resolvedUid;

    try {
      final resStr = await fsQuery('profiles', 'username', '==', jsonEncode(cleanHandle), '');
      final List docs = jsonDecode(resStr);
      if (docs.isNotEmpty) {
        final doc = docs.first;
        final data = doc['data'];
        resolvedName = data['displayName'] ?? data['username'] ?? handle;
        resolvedUid = doc['id'];
      }
    } catch (_) {}

    setState(() {
      _creators.add({
        'uid': resolvedUid,
        'name': resolvedName,
        'role': role.isNotEmpty ? role : 'Contributor',
      });
      _newHandle = '';
      _newRole = '';
    });
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'skeleton-line shimmer-bg', []);
    }

    return div(classes: 'flex-col text-left gap-4', attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px;'}, [
      div(classes: 'flex-col gap-2', [
        for (int i = 0; i < _creators.length; i++)
          div(classes: 'flex-row items-center justify-between bg-gray-50 border border-gray-150 p-2 rounded-md mb-2', attributes: const {'style': 'display: flex; align-items: center; justify-content: space-between;'}, [
            span([text('${_creators[i]['name']} (${_creators[i]['role']})')], attributes: const {'style': 'font-size: 13px; font-weight: 500;'}),
            span(
                classes: 'material-symbols-outlined text-red-500 cursor-pointer',
                attributes: const {'style': 'font-size: 18px;'},
                events: {
                  'click': (e) => setState(() => _creators.removeAt(i))
                },
                [text('remove_circle')]
            )
          ]),

        div(classes: 'flex-row items-center gap-2 mt-2', attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'}, [
          div(classes: 'flex-1', [
            input(
              attributes: {'type': 'text', 'placeholder': '@handle', 'value': _newHandle, 'style': 'margin-bottom: 0; padding: 8px 12px; font-size: 12px;'},
              events: {'input': (e) => _newHandle = getInputValue(e)},
            )
          ]),
          div(classes: 'flex-1', [
            input(
              attributes: {'type': 'text', 'placeholder': 'Role', 'value': _newRole, 'style': 'margin-bottom: 0; padding: 8px 12px; font-size: 12px;'},
              events: {'input': (e) => _newRole = getInputValue(e)},
            )
          ]),
          span(
              classes: 'material-symbols-outlined text-green-600 cursor-pointer',
              attributes: const {'style': 'font-size: 24px;'},
              events: {'click': (e) => _addCreator()},
              [text('add_circle')]
          )
        ])
      ]),

      div(classes: 'flex flex-row justify-between items-center mt-4', [
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
            [text(_saving ? 'Saving...' : 'Save Creators')]
        )
      ])
    ]);
  }
}