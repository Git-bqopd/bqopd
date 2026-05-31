import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../../utils/web_firebase_interop.dart';

/// Safe YouTube IFrame wrapper component, avoiding heavy third-party compilation crashes.
class YoutubePanel extends StatefulComponent {
  final String imageId;
  const YoutubePanel({required this.imageId, super.key});

  @override
  State<YoutubePanel> createState() => _YoutubePanelState();
}

class _YoutubePanelState extends State<YoutubePanel> {
  String? _youtubeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateComponent(YoutubePanel oldComponent) {
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
        text('No video resource linked to this page.')
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