import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';

/// Dedicated inline drawer (bonusRow) YouTube player.
class YoutubeRowPanel extends StatefulComponent {
  final String imageId;
  const YoutubeRowPanel({required this.imageId, super.key});

  @override
  State<YoutubeRowPanel> createState() => _YoutubeRowPanelState();
}

class _YoutubeRowPanelState extends State<YoutubeRowPanel> {
  String? _youtubeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateComponent(YoutubeRowPanel oldComponent) {
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
          _youtubeId = doc['data']['youtubeId'];
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
    if (_youtubeId == null || _youtubeId!.isEmpty) {
      return div(classes: 'p-6 text-center text-gray italic text-xs', [
        Component.text('No video resource linked to this page.')
      ]);
    }
    return div(attributes: const {
      'style': 'width: 100%; aspect-ratio: 16 / 9; background-color: #000; border-radius: 8px; overflow: hidden;'
    }, [
      iframe(
          src: 'https://www.youtube.com/embed/$_youtubeId',
          attributes: const {
            'title': 'YouTube Player',
            'frameborder': '0',
            'allow': 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share',
            'allowfullscreen': 'true',
            'style': 'width: 100%; height: 100%; border: none;'
          },
          []
      )
    ]);
  }
}

/// Dedicated desktop 3rd column (bonusColumn) YouTube player taking over the window.
class YoutubeColumnPanel extends StatelessComponent {
  final String imageId;
  const YoutubeColumnPanel({required this.imageId, super.key});

  @override
  Component build(BuildContext context) {
    return YoutubeRowPanel(imageId: imageId);
  }
}

/// Backwards-compatible alias
typedef YoutubePanel = YoutubeColumnPanel;