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

  @override
  void initState() {
    super.initState();
    _fetchText();
  }

  Future<void> _fetchText() async {
    if (component.imageId.isEmpty) return;

    final res = await fsGetDoc('images/${component.imageId}');
    final doc = jsonDecode(res);
    if (doc['exists'] && mounted) {
      final data = doc['data'];
      setState(() {
        _content = data['text_linked'] ?? data['text_corrected'] ?? data['text_raw'] ?? "Transcription pending.";
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return div([
      div(classes: 'flex-row gap-4 mb-4', [
        button(
            classes: 'nav-pill',
            events: {'click': (e) => setState(() => _fontSize = (_fontSize > 12) ? _fontSize - 2 : 12)},
            [text('A-')]
        ),
        button(
            classes: 'nav-pill',
            events: {'click': (e) => setState(() => _fontSize = (_fontSize < 32) ? _fontSize + 2 : 32)},
            [text('A+')]
        ),
      ]),

      p(
          attributes: {
            'style': 'font-size: ${_fontSize}px; font-family: Georgia, serif; line-height: 1.6; color: #333; white-space: pre-wrap; text-align: justify;'
          },
          [text(_content)]
      )
    ]);
  }
}