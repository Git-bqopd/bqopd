import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'dart:convert';
import '../../utils/web_firebase_interop.dart';

class TextReaderPanel extends StatefulComponent {
  final String imageId;

  const TextReaderPanel({required this.imageId, super.key});

  @override
  State<TextReaderPanel> createState() => _TextReaderPanelState();
}

class _TextReaderPanelState extends State<TextReaderPanel> {
  String _content = "Loading text...";
  double _fontSize = 16.0;

  @override
  void initState() {
    super.initState();
    _fetchText();
  }

  Future<void> _fetchText() async {
    final res = await fsGetDoc('images/${component.imageId}');
    final doc = jsonDecode(res);
    if (doc['exists']) {
      final data = doc['data'];
      setState(() {
        _content = data['text_corrected'] ?? data['text_raw'] ?? "No text available.";
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return div([
      // Simple font size toggle
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