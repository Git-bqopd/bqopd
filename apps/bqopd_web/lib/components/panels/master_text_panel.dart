import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';

/// Interactive corrected text editor panel for Fanzine Folio pages.
/// Allows curators and creators to type directly to save master/corrected text.
class MasterTextPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;

  const MasterTextPanel({
    required this.imageId,
    this.fanzineId,
    super.key,
  });

  @override
  State<MasterTextPanel> createState() => _MasterTextPanelState();
}

class _MasterTextPanelState extends State<MasterTextPanel> {
  String _textValue = '';
  String _aiBaselineText = '';
  bool _loading = true;
  bool _isSaving = false;
  String _statusMessage = '';
  bool _isError = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadText();
    }
  }

  @override
  void didUpdateComponent(MasterTextPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId && kIsWeb) {
      _loadText();
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadText() async {
    if (component.imageId.isEmpty) {
      setState(() {
        _textValue = '';
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] && mounted) {
        final data = doc['data'] as Map<String, dynamic>;
        setState(() {
          _textValue = data['text_corrected'] ?? data['text_raw'] ?? data['text'] ?? '';
          _aiBaselineText = data['text_corrected_ai'] ?? '';
          _loading = false;
        });
      } else {
        setState(() {
          _textValue = '';
          _loading = false;
        });
      }
    } catch (e) {
      print('[MASTER TEXT PANEL ERROR] Loading failed: $e');
      setState(() {
        _textValue = '';
        _loading = false;
      });
    }
  }

  int _calculateEditDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }

  Future<void> _saveText() async {
    if (component.imageId.isEmpty || _isSaving) return;

    setState(() {
      _isSaving = true;
      _statusMessage = 'Saving page text...';
      _isError = false;
    });

    try {
      final updates = <String, dynamic>{
        'text_corrected': _textValue,
        'needs_linking': true,
      };

      if (_aiBaselineText.isNotEmpty) {
        final int score = _calculateEditDistance(_aiBaselineText, _textValue);
        updates['human_correction_score'] = score;
        if (score > 0) {
          updates['isTrainingData'] = true;
        }
      }

      await fsUpdateDoc('images/${component.imageId}', jsonEncode(updates));

      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusMessage = 'Saved page text successfully!';
          _isError = false;
        });
        _resetStatusTimer();
      }
    } catch (e) {
      print('[MASTER TEXT PANEL ERROR] Save failed: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusMessage = 'Failed to save: ${e.toString()}';
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
      return div(classes: 'flex-col gap-2 py-4', [
        div(classes: 'skeleton-line shimmer-bg', []),
        div(classes: 'skeleton-line medium shimmer-bg', []),
        div(classes: 'skeleton-line shimmer-bg', []),
        div(classes: 'skeleton-line short shimmer-bg', []),
      ]);
    }

    return div(classes: 'flex-col text-left', [
      // Implement the .grow-wrap element mirroring architecture
      div(
          classes: 'grow-wrap',
          attributes: {
            'data-replicated-value': _textValue,
          },
          [
            textarea(
                classes: 'border border-gray-300 rounded-md',
                attributes: {
                  'placeholder': 'Start typing directly in the editor to create or correct page text...',
                  'oninput': 'this.parentNode.dataset.replicatedValue = this.value',
                },
                events: {
                  'input': (e) {
                    setState(() {
                      _textValue = getInputValue(e);
                    });
                  }
                },
                [text(_textValue)]
            )
          ]
      ),
      div(classes: 'flex flex-row justify-between items-center mt-3', [
        span([
          text(_statusMessage)
        ], classes: _isError ? 'text-xs text-red-500 font-bold' : 'text-xs text-green-600 font-bold'),
        button(
            classes: 'btn-primary nav-pill mb-0',
            attributes: {
              'style': 'padding: 8px 16px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
              if (_isSaving) 'disabled': 'true'
            },
            events: {
              'click': (e) => _saveText()
            },
            [
              text(_isSaving ? 'Saving...' : 'Save Text')
            ]
        )
      ])
    ]);
  }
}