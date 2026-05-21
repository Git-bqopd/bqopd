import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';

class TextReaderPanel extends StatefulComponent {
  final String imageId;

  const TextReaderPanel({required this.imageId, super.key});

  @override
  State<TextReaderPanel> createState() => _TextReaderPanelState();
}

class _TextReaderPanelState extends State<TextReaderPanel> {
  String _content = "Loading digitized text...";
  double _fontSize = 16.0;
  bool _loading = true; // High-fidelity state tracking

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _fetchText();
    }
  }

  @override
  void didUpdateComponent(TextReaderPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId && kIsWeb) {
      _fetchText();
    }
  }

  Future<void> _fetchText() async {
    if (component.imageId.isEmpty) {
      setState(() {
        _content = "Transcription pending (No Image ID).";
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
        final data = doc['data'];

        // Match Flutter's "Gold Master" hierarchy
        final String? text = data['text_linked'] ??
            data['text_corrected'] ??
            data['text_raw'] ??
            data['text']; // Legacy fallback

        setState(() {
          _content = (text != null && text.trim().isNotEmpty)
              ? text
              : "Transcription pending for this page.";
          _loading = false;
        });
      } else {
        setState(() {
          _content = "Image record not found in database.";
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _content = "Error loading text: $e";
        _loading = false;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return div([
      div(classes: 'flex-row gap-4 mb-4', [
        button(
            classes: 'nav-pill',
            events: {'click': (e) => setState(() => _fontSize = (_fontSize > 10) ? _fontSize - 2 : 10)},
            [text('A-')]
        ),
        button(
            classes: 'nav-pill',
            events: {'click': (e) => setState(() => _fontSize = (_fontSize < 48) ? _fontSize + 2 : 48)},
            [text('A+')]
        ),
      ]),

      // Swapped dry text-loader for shimmering markdown text skeletons
      if (_loading)
        div(classes: 'flex-col gap-2 py-4', [
          div(classes: 'skeleton-line shimmer-bg', []),
          div(classes: 'skeleton-line medium shimmer-bg', []),
          div(classes: 'skeleton-line shimmer-bg', []),
          div(classes: 'skeleton-line short shimmer-bg', []),
        ])
      else
        p(
            attributes: {
              'style': 'font-size: ${_fontSize}px; font-family: Georgia, serif; line-height: 1.6; color: #333; white-space: pre-wrap; text-align: justify;'
            },
            [text(_content)]
        )
    ]);
  }
}