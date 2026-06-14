import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/publisher_compiler.dart';
import '../../utils/web_utils.dart';

/// Interactive Wiki-Link editor panel for Fanzine Folio pages.
/// Aligns with Clean Architecture by delegating GCS asset compiler steps to the centralized service.
class LinkedTextPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;

  const LinkedTextPanel({
    required this.imageId,
    this.fanzineId,
    super.key,
  });

  @override
  State<LinkedTextPanel> createState() => _LinkedTextPanelState();
}

class _LinkedTextPanelState extends State<LinkedTextPanel> {
  String _textValue = '';
  String _correctedText = '';
  String _aiBaselineText = '';
  bool _loading = true;
  bool _isSaving = false;
  String _statusMessage = '';
  bool _isError = false;
  Timer? _statusTimer;
  bool _isTemplate = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadTextData();
    }
  }

  @override
  void didUpdateComponent(LinkedTextPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId && kIsWeb) {
      _loadTextData();
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTextData() async {
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
          _textValue = data['text_linked'] ?? '';
          _correctedText = data['text_corrected'] ?? data['text'] ?? '';
          _aiBaselineText = data['text_linked_ai'] ?? '';
          _isTemplate = data['type'] == 'template' || data['templateId'] == 'basic_text';
          // Fallback to Corrected/Clean text on empty linked baseline
          if (_textValue.trim().isEmpty && _correctedText.isNotEmpty) {
            _textValue = _correctedText;
          }
          _loading = false;
        });
      } else {
        setState(() {
          _textValue = '';
          _loading = false;
        });
      }
    } catch (e) {
      print('[LINKED PANEL ERROR] Loading failed: $e');
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

  Future<void> _saveLinkedText() async {
    if (component.imageId.isEmpty || _isSaving) return;
    setState(() {
      _isSaving = true;
      _statusMessage = 'Saving wiki-links and entities...';
      _isError = false;
    });
    try {
      // Parse manual bracket annotations [[Label|ref]] out of content
      final regex = RegExp(r'\[\[(.*?)\]\]');
      final matches = regex.allMatches(_textValue);
      final List<String> manualEntities = [];
      for (final m in matches) {
        final content = m.group(1) ?? '';
        final parts = content.split('|');
        if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
          manualEntities.add(parts[0].trim());
        }
      }

      final updates = <String, dynamic>{
        'text_linked': _textValue,
        'detected_entities': manualEntities,
        'needs_linking': false,
      };

      if (_aiBaselineText.isNotEmpty) {
        final int score = _calculateEditDistance(_aiBaselineText, _textValue);
        updates['human_linking_score'] = score;
        if (score > 0) {
          updates['isTrainingData'] = true;
        }
      }

      // REDIRECT IF TEMPLATE PAGE: Re-compile WebPs immediately on save via our centralized service
      if (_isTemplate) {
        setState(() {
          _statusMessage = 'Re-compiling WebP page layouts...';
        });
        final fanzineId = component.fanzineId ?? 'unknown_fanzine';
        final compiledUrls = await PublisherCompiler.compileAndPublish(
          fanzineId: fanzineId,
          imageId: component.imageId,
          text: _textValue,
        );
        updates.addAll(compiledUrls);
      }

      await fsUpdateDoc('images/${component.imageId}', jsonEncode(updates));

      // Bubble up manual entities to the parent Fanzine
      if (component.fanzineId != null && manualEntities.isNotEmpty) {
        await fsUpdateDoc('fanzines/${component.fanzineId}', jsonEncode({
          'draftEntities': WebFieldValue.arrayUnion(manualEntities)
        }));
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusMessage = 'Wiki-Links saved successfully!';
          _isError = false;
        });
        _resetStatusTimer();
      }
    } catch (e) {
      print('[LINKED PANEL ERROR] Save failed: $e');
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
      return div(
        [
          div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 100%;'}),
          div([], classes: 'skeleton-line medium shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 85%;'}),
          div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 100%;'}),
          div([], classes: 'skeleton-line short shimmer-bg', attributes: const {'style': 'height: 12px; border-radius: 4px; width: 60%;'}),
        ],
        classes: 'flex-col gap-2 py-4',
        attributes: const {'style': 'display: flex; flex-direction: column; gap: 8px; width: 100%;'},
      );
    }
    return div(
      [
        // Implement the .grow-wrap element mirroring architecture
        div(
          [
            textarea(
                classes: 'border border-gray-300 rounded-md',
                attributes: {
                  'placeholder': 'Use markdown [[Wiki-Links]] to identify profiles inside the master clean text.',
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
          ],
          classes: 'grow-wrap',
          attributes: {
            'data-replicated-value': _textValue,
          },
        ),
        // Actions / Status Bar row
        div(
          [
            span(
                [text(_statusMessage)],
                classes: _isError ? 'text-xs text-red-500 font-bold' : 'text-xs text-green-600 font-bold'
            ),
            button(
              [text(_isSaving ? 'Saving...' : 'Save Links')],
              classes: 'btn-primary nav-pill mb-0',
              attributes: {
                'style': 'padding: 8px 16px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
                if (_isSaving) 'disabled': 'true'
              },
              events: {
                'click': (e) => _saveLinkedText()
              },
            )
          ],
          classes: 'flex flex-row justify-between items-center mt-3',
          attributes: const {'style': 'display: flex; flex-direction: row; justify-content: space-between; align-items: center; margin-top: 12px;'},
        )
      ],
      classes: 'flex-col text-left',
      attributes: const {'style': 'display: flex; flex-direction: column; width: 100%;'},
    );
  }
}