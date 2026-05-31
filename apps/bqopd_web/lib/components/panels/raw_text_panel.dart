import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';

/// Lightweight panel component displaying uncorrected raw OCR transcription data.
class RawTextPanel extends StatefulComponent {
  final String imageId;
  const RawTextPanel({required this.imageId, super.key});

  @override
  State<RawTextPanel> createState() => _RawTextPanelState();
}

class _RawTextPanelState extends State<RawTextPanel> {
  String _rawText = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateComponent(RawTextPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.imageId != component.imageId) {
      _load();
    }
  }

  Future<void> _load() async {
    if (component.imageId.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] == true) {
        setState(() {
          _rawText = doc['data']['text_raw'] ?? '[No raw OCR text detected]';
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'skeleton-line shimmer-bg', []);
    }
    return div([
      p([text(_rawText)], attributes: const {
        'style': "font-family: Courier, monospace; font-size: 13px; line-height: 1.5; white-space: pre-wrap; word-break: break-word; text-align: left; color: #333;"
      })
    ]);
  }
}