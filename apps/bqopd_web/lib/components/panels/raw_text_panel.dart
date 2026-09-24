import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';

/// Dedicated inline drawer (bonusRow) view for uncorrected raw OCR transcription data.
class RawTextRowPanel extends StatefulComponent {
  final String imageId;
  const RawTextRowPanel({required this.imageId, super.key});

  @override
  State<RawTextRowPanel> createState() => _RawTextRowPanelState();
}

class _RawTextRowPanelState extends State<RawTextRowPanel> {
  String _rawText = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateComponent(RawTextRowPanel oldComponent) {
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

/// Dedicated desktop 3rd column (bonusColumn) view for raw OCR transcription data.
/// Styled as an inspection card with selectable monospace output.
class RawTextColumnPanel extends StatefulComponent {
  final String imageId;
  const RawTextColumnPanel({required this.imageId, super.key});

  @override
  State<RawTextColumnPanel> createState() => _RawTextColumnPanelState();
}

class _RawTextColumnPanelState extends State<RawTextColumnPanel> {
  String _rawText = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateComponent(RawTextColumnPanel oldComponent) {
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
    return div(
        [
          div(
              [
                span([text('UNFILTERED OCR PAYLOAD')], attributes: const {
                  'style': 'font-size: 10px; font-weight: bold; color: #64748b; letter-spacing: 0.5px;'
                }),
              ],
              attributes: const {'style': 'margin-bottom: 8px;'}
          ),
          p([text(_rawText)], attributes: const {
            'style': "font-family: Courier, monospace; font-size: 12.5px; line-height: 1.5; white-space: pre-wrap; word-break: break-word; text-align: left; color: #334155; background: #f8fafc; padding: 12px; border-radius: 6px; border: 1px solid #e2e8f0;"
          })
        ],
        attributes: const {'style': 'width: 100%;'}
    );
  }
}

/// Backwards-compatible alias for the default row panel
typedef RawTextPanel = RawTextRowPanel;