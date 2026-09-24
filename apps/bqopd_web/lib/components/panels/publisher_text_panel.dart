import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/publisher_compiler.dart';
import '../../utils/web_utils.dart';

/// Dedicated inline drawer (bonusRow) publisher layout editor.
class PublisherTextRowPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  const PublisherTextRowPanel({required this.imageId, this.fanzineId, super.key});

  @override
  State<PublisherTextRowPanel> createState() => _PublisherTextRowPanelState();
}

class _PublisherTextRowPanelState extends State<PublisherTextRowPanel> {
  String _textValue = '';
  bool _loading = true;
  bool _saving = false;
  String _statusMessage = '';
  bool _isError = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadTextData();
    }
  }

  @override
  void didUpdateComponent(PublisherTextRowPanel oldComponent) {
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

  Future<void> _save() async {
    if (component.imageId.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _statusMessage = 'Compiling & publishing...';
      _isError = false;
    });
    try {
      final fanzineId = component.fanzineId ?? 'unknown_fanzine';
      final compiledUrls = await PublisherCompiler.compileAndPublish(
        fanzineId: fanzineId,
        imageId: component.imageId,
        text: _textValue,
      );
      final Map<String, dynamic> updates = {
        'text': _textValue,
        'text_corrected': _textValue,
        'text_linked': _textValue,
        'needs_ai_cleaning': false,
        'needs_linking': true,
      };
      updates.addAll(compiledUrls);
      await fsUpdateDoc('images/${component.imageId}', jsonEncode(updates));
      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Page published!';
          _isError = false;
        });
        _statusTimer?.cancel();
        _statusTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _statusMessage = '');
        });
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

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
        [
          div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'height: 14px; width: 100%; border-radius: 4px;'}),
        ],
        classes: 'flex-col gap-2 py-4',
      );
    }
    return div(
      [
        div(
          [
            textarea(
                classes: 'border border-gray-300 rounded-md',
                attributes: {
                  'placeholder': 'Type publisher markdown text here...',
                  'oninput': 'this.parentNode.dataset.replicatedValue = this.value',
                },
                events: {
                  'input': (e) => setState(() => _textValue = getInputValue(e))
                },
                [text(_textValue)]
            )
          ],
          classes: 'grow-wrap',
          attributes: {'data-replicated-value': _textValue},
        ),
        div(
          [
            span([text(_statusMessage)], classes: _isError ? 'text-xs text-red-500 font-bold' : 'text-xs text-green-600 font-bold'),
            button(
              [text(_saving ? 'Publishing...' : 'Publish Page')],
              classes: 'btn-primary nav-pill mb-0',
              attributes: {
                'style': 'padding: 8px 16px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
                if (_saving) 'disabled': 'true'
              },
              events: {'click': (e) => _save()},
            )
          ],
          classes: 'flex flex-row justify-between items-center mt-3',
        )
      ],
      classes: 'flex-col text-left gap-2',
    );
  }
}

/// Dedicated desktop 3rd column (bonusColumn) publisher workstation.
/// Hosts full gallery insertion and live WebP compiler controls.
class PublisherTextColumnPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;
  const PublisherTextColumnPanel({required this.imageId, this.fanzineId, super.key});

  @override
  State<PublisherTextColumnPanel> createState() => _PublisherTextColumnPanelState();
}

class _PublisherTextColumnPanelState extends State<PublisherTextColumnPanel> {
  String _textValue = '';
  bool _loading = true;
  bool _saving = false;
  String _statusMessage = '';
  bool _isError = false;
  Timer? _statusTimer;

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
  void didUpdateComponent(PublisherTextColumnPanel oldComponent) {
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
      _statusMessage = 'Compiling & publishing page layout...';
      _isError = false;
    });
    try {
      final fanzineId = component.fanzineId ?? 'unknown_fanzine';
      final compiledUrls = await PublisherCompiler.compileAndPublish(
        fanzineId: fanzineId,
        imageId: component.imageId,
        text: _textValue,
      );
      final Map<String, dynamic> updates = {
        'text': _textValue,
        'text_corrected': _textValue,
        'text_linked': _textValue,
        'needs_ai_cleaning': false,
        'needs_linking': true,
      };
      updates.addAll(compiledUrls);
      await fsUpdateDoc('images/${component.imageId}', jsonEncode(updates));
      if (mounted) {
        setState(() {
          _saving = false;
          _statusMessage = 'Page published successfully!';
          _isError = false;
        });
        _statusTimer?.cancel();
        _statusTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _statusMessage = '');
        });
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

  void _insertImageAsset(String shortName) {
    setState(() {
      _textValue += "\n{{$shortName}}\n";
    });
  }

  void _insertTemplateAsset(String shortName, int templateNum) {
    setState(() {
      _textValue += "\n{{$templateNum|$shortName|Caption text}}\n";
    });
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(
        [
          div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'height: 14px; width: 100%; border-radius: 4px;'}),
        ],
        classes: 'flex-col gap-2 py-4',
      );
    }
    final folioImages = _userImages.where((img) {
      if (component.fanzineId == null || component.fanzineId!.isEmpty) return false;
      final List usedIn = img['usedInFanzines'] ?? [];
      final String? contextId = img['folioContext'];
      return contextId == component.fanzineId || usedIn.contains(component.fanzineId);
    }).toList();

    folioImages.sort((a, b) {
      final aT = a['timestamp'] ?? a['createdAt'] ?? '';
      final bT = b['timestamp'] ?? b['createdAt'] ?? '';
      return aT.toString().compareTo(bT.toString());
    });

    final Map<String, String> imageShortNames = {};
    for (int i = 0; i < folioImages.length; i++) {
      final String id = folioImages[i]['id'] ?? '';
      if (id.isNotEmpty) imageShortNames[id] = "img${(i + 1).toString().padLeft(2, '0')}";
    }

    return div(
      [
        div(
          [
            textarea(
                classes: 'border border-gray-300 rounded-md',
                attributes: {
                  'placeholder': 'Type markdown layout text here...',
                  'oninput': 'this.parentNode.dataset.replicatedValue = this.value',
                  'style': 'min-height: 140px;',
                },
                events: {
                  'input': (e) => setState(() => _textValue = getInputValue(e))
                },
                [text(_textValue)]
            )
          ],
          classes: 'grow-wrap',
          attributes: {'data-replicated-value': _textValue},
        ),
        div(
          [
            span([text(_statusMessage)], classes: _isError ? 'text-xs text-red-500 font-bold' : 'text-xs text-green-600 font-bold'),
            button(
              [text(_saving ? 'Publishing...' : 'Publish Page')],
              classes: 'btn-primary nav-pill mb-0',
              attributes: {
                'style': 'padding: 8px 18px; font-size: 12px; height: 32px; display: inline-flex; align-items: center; width: auto; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer;',
                if (_saving) 'disabled': 'true'
              },
              events: {'click': (e) => _save()},
            )
          ],
          classes: 'flex flex-row justify-between items-center',
        ),
        div([], attributes: const {'style': 'height: 1px; background-color: #eee; margin: 8px 0;'}),
        div(
          [
            p([text('INSERT FROM YOUR GALLERY')], attributes: const {'style': 'font-size: 10px; font-weight: bold; color: #888; margin: 0 0 8px 0;'}),
            if (_loadingImages)
              div([], classes: 'skeleton-line shimmer-bg', attributes: const {'style': 'height: 16px; width: 100%; border-radius: 4px;'})
            else if (folioImages.isEmpty)
              p([text('No images in this folio.')], classes: 'text-xs text-gray italic')
            else
              div(
                [
                  for (var img in folioImages)
                    div([
                      div(
                          [],
                          attributes: {
                            'style': 'width: 100%; aspect-ratio: 5/8; background-color: #f1f1f1; background-image: url("${img['gridUrl'] ?? img['fileUrl'] ?? ''}"); background-size: cover; background-position: center; border-radius: 4px; border: 1px solid #ddd; cursor: pointer;'
                          },
                          events: {'click': (e) => _insertImageAsset(imageShortNames[img['id']] ?? 'img')}
                      ),
                      span([text('{{${imageShortNames[img['id']] ?? 'img'}}}')], attributes: const {'style': 'font-size: 9px; color: #6750A4; font-family: monospace;'}),
                      button([text('+ T1')], attributes: const {'style': 'font-size: 8px; cursor: pointer;'}, events: {'click': (e) => _insertTemplateAsset(imageShortNames[img['id']] ?? 'img', 1)}),
                    ], attributes: const {'style': 'display: flex; flex-direction: column; align-items: center; gap: 2px;'}),
                ],
                attributes: const {'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(76px, 1fr)); gap: 10px; width: 100%;'},
              )
          ],
          classes: 'flex-col gap-2',
        )
      ],
      classes: 'flex-col text-left gap-4',
    );
  }
}

/// Backwards-compatible alias
typedef PublisherTextPanel = PublisherTextRowPanel;