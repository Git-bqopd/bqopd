import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';

/// Live interactive text configuration and image insertion editor panel.
/// Mirroring standard old publisher capability inside the settings panel context.
class PublisherTextPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  const PublisherTextPanel({required this.imageId, this.fanzineId, super.key});

  @override
  State<PublisherTextPanel> createState() => _PublisherTextPanelState();
}

class _PublisherTextPanelState extends State<PublisherTextPanel> {
  String _textValue = '';
  bool _loading = true;
  bool _saving = false;
  String _statusMessage = '';
  bool _isError = false;
  Timer? _statusTimer;

  // Real-time image asset insertions
  List<Map<String, dynamic>> _userImages = [];
  bool _loadingImages = true;
  dynamic _imagesUnsub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadTextData();
      _listenToUserImages();
    }
  }

  @override
  void didUpdateComponent(PublisherTextPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId && kIsWeb) {
      _loadTextData();
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _imagesUnsub?.cancel();
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
    setState(() => _loading = true);
    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] == true) {
        setState(() {
          _textValue = doc['data']['text_corrected'] ?? doc['data']['text'] ?? '';
          _loading = false;
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _listenToUserImages() {
    _imagesUnsub?.cancel();
    _imagesUnsub = null;

    final uid = getCurrentUserId();
    if (uid == null) {
      setState(() {
        _userImages = [];
        _loadingImages = false;
      });
      return;
    }

    _imagesUnsub = fsListenQuery('images', 'uploaderId', '==', jsonEncode(uid), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr);
        final images = decoded.map((d) {
          final data = d['data'] as Map<String, dynamic>;
          data['id'] = d['id'];
          return data;
        }).toList();

        if (mounted) {
          setState(() {
            _userImages = images;
            _loadingImages = false;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _save() async {
    if (component.imageId.isEmpty || _saving) return;

    setState(() {
      _saving = true;
      _statusMessage = 'Publishing page contents...';
      _isError = false;
    });

    try {
      await fsUpdateDoc('images/${component.imageId}', jsonEncode({
        'text': _textValue,
        'text_corrected': _textValue,
        'text_linked': _textValue,
        'needs_ai_cleaning': false,
        'needs_linking': true, // Auto-trigger Wiki-Link pipeline
      }));

      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Page published successfully!';
          _isError = false;
        });
        _resetStatusTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Publish error: $e';
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

  /// Inserts a selected image url placeholder directly into the text editor at the cursor or tail.
  void _insertImageAsset(String url) {
    final String imageTag = "\n{{IMAGE: $url}}\n";
    setState(() {
      _textValue += imageTag;
    });
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'flex-col gap-2 py-4', [
        div(classes: 'skeleton-line shimmer-bg', []),
        div(classes: 'skeleton-line medium shimmer-bg', []),
      ]);
    }

    // Filter user's images that belong to this fanzine
    final folioImages = _userImages.where((img) {
      if (component.fanzineId == null || component.fanzineId!.isEmpty) {
        return false;
      }
      final List usedIn = img['usedInFanzines'] ?? [];
      final String? contextId = img['folioContext'];
      return contextId == component.fanzineId || usedIn.contains(component.fanzineId);
    }).toList();

    return div(classes: 'flex-col text-left gap-4', attributes: const {'style': 'display: flex; flex-direction: column; gap: 16px;'}, [
      p([text('Page Layout Editor')], attributes: const {
        'style': 'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; margin: 0;'
      }),

      div(classes: 'grow-wrap', attributes: {'data-replicated-value': _textValue}, [
        textarea(
            classes: 'border border-gray-300 rounded-md',
            attributes: {
              'placeholder': 'Type markdown text here. Write headings with # or ## and tap images in your gallery below to instantly insert {{IMAGE}} placeholders.',
              'oninput': 'this.parentNode.dataset.replicatedValue = this.value',
            },
            events: {
              'input': (e) => setState(() => _textValue = getInputValue(e))
            },
            [text(_textValue)]
        )
      ]),

      // Action and confirmation bar
      div(classes: 'flex flex-row justify-between items-center', [
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
            [text(_saving ? 'Publishing...' : 'Publish Page')]
        )
      ]),

      div([], attributes: const {'style': 'height: 1px; background-color: #eee;'}),

      // Click to insert images grid
      div(classes: 'flex-col gap-2', [
        p([text('INSERT FROM YOUR GALLERY')], attributes: const {
          'style': 'font-size: 10px; font-weight: bold; color: #888; letter-spacing: 0.5px; margin: 0 0 8px 0;'
        }),
        if (_loadingImages)
          div(classes: 'skeleton-line shimmer-bg', [])
        else if (folioImages.isEmpty)
          p([text('No images in this folio to insert. Upload images first in the Upload tab of this fanzine.')], attributes: const {
            'style': 'font-size: 11px; color: #999; font-style: italic;'
          })
        else
          div(attributes: const {
            'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(64px, 1fr)); gap: 8px;'
          }, [
            for (var img in folioImages)
              div(
                  attributes: {
                    'style': 'aspect-ratio: 5/8; background-color: #f1f1f1; background-image: url("${img['gridUrl'] ?? img['fileUrl'] ?? ''}"); background-size: cover; background-position: center; border-radius: 4px; border: 1px solid #ddd; cursor: pointer;'
                  },
                  events: {
                    'click': (e) => _insertImageAsset(img['fileUrl'] ?? img['gridUrl'] ?? '')
                  },
                  []
              )
          ])
      ])
    ]);
  }
}