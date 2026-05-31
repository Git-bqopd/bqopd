import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../utils/unsaved_fanzine_registry.dart';

/// Interactive Wiki-Link editor panel for Fanzine Folio pages.
/// Allows curators and creators to inject custom [[Wiki Links]] and manage entities.
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

  // Target template config mapping inside the Wiki-Links baseline
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
      final uid = getCurrentUserId() ?? 'system_web';

      // Parse manual bracket annotations [[Label|ref]] out of content
      final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
      final matches = regex.allMatches(_textValue);
      final List<String> manualEntities = [];

      for (final m in matches) {
        final name = m.group(1)?.trim();
        if (name != null && name.isNotEmpty) {
          manualEntities.add(name);
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

      // REDIRECT IF TEMPLATE PAGE: Re-compile WebPs immediately on save
      if (_isTemplate) {
        setState(() {
          _statusMessage = 'Re-compiling WebP page layouts...';
        });

        final resultJson = await renderPublisherPage(_textValue);
        final decoded = jsonDecode(resultJson);

        final String origBase64 = decoded['original'];
        final String listBase64 = decoded['list'];
        final String gridBase64 = decoded['grid'];

        final origBytes = base64Decode(origBase64);
        final listBytes = base64Decode(listBase64);
        final gridBytes = base64Decode(gridBase64);

        final String fanzineId = component.fanzineId ?? 'unknown_fanzine';
        final String baseDir = 'uploads/$uid/folio_assets/$fanzineId/${component.imageId}';

        final urls = await Future.wait([
          stUpload('$baseDir/original.webp', origBytes, 'image/webp'),
          stUpload('$baseDir/list.webp', listBytes, 'image/webp'),
          stUpload('$baseDir/grid.webp', gridBytes, 'image/webp'),
        ]);

        final cb = DateTime.now().millisecondsSinceEpoch;
        final fileUrl = '${urls[0]}&cb=$cb';
        final listUrl = '${urls[1]}&cb=$cb';
        final gridUrl = '${urls[2]}&cb=$cb';

        updates['fileUrl'] = fileUrl;
        updates['listUrl'] = listUrl;
        updates['gridUrl'] = gridUrl;

        // Sync layout page documents as well
        if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
          final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
          final idx = pages.indexWhere((p) => p.imageId == component.imageId);
          if (idx != -1) {
            final p = pages[idx];
            pages[idx] = FanzinePage(
              id: p.id,
              pageNumber: p.pageNumber,
              imageId: p.imageId,
              imageUrl: fileUrl,
              gridUrl: gridUrl,
              listUrl: listUrl,
              storagePath: p.storagePath,
              status: 'ready',
              templateId: p.templateId,
              spreadPosition: p.spreadPosition,
              sidePreference: p.sidePreference,
              width: p.width,
              height: p.height,
            );
            UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(pages);
          }
        } else {
          final pagesRes = await fsQuery('fanzines/$fanzineId/pages', 'imageId', '==', jsonEncode(component.imageId), '');
          final List pageDocs = jsonDecode(pagesRes) as List;
          for (var pageDoc in pageDocs) {
            final pageId = pageDoc['id'] ?? '';
            if (pageId.isNotEmpty) {
              await fsUpdateDoc('fanzines/$fanzineId/pages/$pageId', jsonEncode({
                'imageUrl': fileUrl,
                'listUrl': listUrl,
                'gridUrl': gridUrl,
                'status': 'ready',
              }));
            }
          }
        }
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
          ]
      ),

      // Actions / Status Bar row
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
              'click': (e) => _saveLinkedText()
            },
            [
              text(_isSaving ? 'Saving...' : 'Save Links')
            ]
        )
      ])
    ]);
  }
}