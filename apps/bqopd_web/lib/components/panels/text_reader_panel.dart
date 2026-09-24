import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';

/// Helper to render markdown and wiki-links into styled components
List<Component> renderWikilinkSpans(
    String textContent,
    Map<String, Map<String, dynamic>> loadedProfiles,
    BuildContext context,
    ) {
  final List<Component> children = [];
  final regex = RegExp(r'\[\[(.*?)\]\]');
  int currentIndex = 0;
  final matches = regex.allMatches(textContent);

  for (final match in matches) {
    if (match.start > currentIndex) {
      children.add(Component.text(textContent.substring(currentIndex, match.start)));
    }
    final content = match.group(1) ?? '';
    final parts = content.split('|');
    String display = '';
    String? ref;

    if (parts.length == 1) {
      display = parts[0].trim();
    } else if (parts.length == 2) {
      if (parts[1].contains(':')) {
        display = parts[0].trim();
        ref = parts[1].trim();
      } else {
        display = parts[1].trim();
      }
    } else if (parts.length >= 3) {
      display = parts[1].trim();
      ref = parts[2].trim();
    }

    if (ref != null) {
      if (ref.startsWith('user:')) {
        final uid = ref.substring(5);
        final profile = loadedProfiles[uid];
        final String? username = profile?['username'];
        if (profile != null && username != null && username.isNotEmpty) {
          children.add(a(
            href: '/@$username',
            attributes: const {
              'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: underline; color: black; cursor: pointer;'
            },
            events: {
              'click': (e) {
                e.preventDefault();
                Router.of(context).push('/@$username');
              }
            },
            [Component.text(display)],
          ));
        } else {
          children.add(span(
            attributes: const {
              'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: none; color: black; cursor: default;'
            },
            [Component.text(display)],
          ));
        }
      } else if (ref.startsWith('address:')) {
        final addressVal = ref.substring(8);
        final encodedAddr = Uri.encodeComponent(addressVal);
        children.add(a(
          href: 'https://www.google.com/maps/search/?api=1&query=$encodedAddr',
          attributes: const {
            'target': '_blank',
            'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: underline; color: #16a34a; cursor: pointer; display: inline-flex; align-items: center; gap: 2px;'
          },
          [
            span(
              [Component.text('pin_drop')],
              classes: 'material-symbols-outlined',
              attributes: const {'style': 'font-size: 14px; margin-right: 2px; vertical-align: middle; display: inline-block;'},
            ),
            Component.text(display),
          ],
        ));
      } else {
        children.add(span(
          attributes: const {
            'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: none; color: black; cursor: default;'
          },
          [Component.text(display)],
        ));
      }
    } else {
      children.add(span(
        attributes: const {
          'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: none; color: black; cursor: default;'
        },
        [Component.text(display)],
      ));
    }
    currentIndex = match.end;
  }

  if (currentIndex < textContent.length) {
    children.add(Component.text(textContent.substring(currentIndex)));
  }
  return children;
}

/// Dedicated inline drawer (bonusRow) text reader.
/// Includes A- and A+ font sizing triggers.
class TextReaderRowPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;

  const TextReaderRowPanel({
    required this.imageId,
    this.fanzineId,
    super.key,
  });

  @override
  State<TextReaderRowPanel> createState() => _TextReaderRowPanelState();
}

class _TextReaderRowPanelState extends State<TextReaderRowPanel> {
  String _content = "Loading digitized text...";
  double _fontSize = 16.0;
  bool _loading = true;
  Map<String, Map<String, dynamic>> _loadedProfiles = {};

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _fetchText();
    }
  }

  @override
  void didUpdateComponent(TextReaderRowPanel oldComponent) {
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

    setState(() => _loading = true);
    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] && mounted) {
        final data = doc['data'];
        final String? textVal = data['text_linked'] ??
            data['text_corrected'] ??
            data['text_raw'] ??
            data['text'];
        final resolvedText = (textVal != null && textVal.trim().isNotEmpty)
            ? textVal
            : "Transcription pending for this page.";
        final String fullyResolvedText = await resolveAndReplaceShortcodes(
          component.fanzineId ?? '',
          resolvedText,
        );
        setState(() {
          _content = fullyResolvedText;
          _loading = false;
        });
        _loadProfiles(fullyResolvedText);
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

  Future<void> _loadProfiles(String textContent) async {
    final regex = RegExp(r'\[\[(.*?)\]\]');
    final matches = regex.allMatches(textContent);
    final Set<String> uidsToFetch = {};

    for (final m in matches) {
      final content = m.group(1) ?? '';
      final parts = content.split('|');
      String? ref;
      if (parts.length == 2 && parts[1].contains(':')) {
        ref = parts[1].trim();
      } else if (parts.length >= 3) {
        ref = parts[2].trim();
      }
      if (ref != null && ref.startsWith('user:')) {
        final uid = ref.substring(5);
        if (!_loadedProfiles.containsKey(uid)) {
          uidsToFetch.add(uid);
        }
      }
    }

    if (uidsToFetch.isEmpty) return;

    final Map<String, Map<String, dynamic>> fetchedProfiles = {};
    for (var uid in uidsToFetch) {
      try {
        final res = await fsGetDoc('profiles/$uid');
        final doc = jsonDecode(res);
        if (doc['exists'] == true) {
          fetchedProfiles[uid] = doc['data'] as Map<String, dynamic>;
        }
      } catch (_) {}
    }

    if (mounted && fetchedProfiles.isNotEmpty) {
      setState(() {
        _loadedProfiles.addAll(fetchedProfiles);
      });
    }
  }

  List<Component> _renderLines(String textContent) {
    final lines = textContent.split('\n');
    final List<Component> lineComponents = [];
    final headerRegex = RegExp(r'^(#{1,6})\s+(.*)$');

    for (var line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) {
        lineComponents.add(div([], attributes: const {'style': 'height: 14px;'}));
        continue;
      }
      final headerMatch = headerRegex.firstMatch(cleanLine);
      if (headerMatch != null) {
        final level = headerMatch.group(1)!.length;
        final content = headerMatch.group(2)!.trim();
        final double headerSize = _fontSize + (4.0 * (7 - level));
        final headingChildren = renderWikilinkSpans(content, _loadedProfiles, context);
        lineComponents.add(h2(headingChildren, attributes: {
          'style': 'font-size: ${headerSize}px; font-family: Impact, Charcoal, "Arial Black", sans-serif; line-height: 1.2; color: #111; margin: 16px 0 8px 0; font-weight: normal;'
        }));
      } else {
        lineComponents.add(p(
          renderWikilinkSpans(cleanLine, _loadedProfiles, context),
          attributes: {
            'style': 'font-size: ${_fontSize}px; font-family: Arial, Helvetica, sans-serif; line-height: 1.6; color: #2D3748; text-align: justify; margin: 0 0 12px 0;'
          },
        ));
      }
    }
    return lineComponents;
  }

  @override
  Component build(BuildContext context) {
    return div(
      attributes: const {
        'style': 'position: relative; width: 100%; box-sizing: border-box; display: flex; flex-direction: column;'
      },
      [
        div(
          classes: 'flex-row gap-2',
          attributes: const {
            'style': 'position: absolute; top: 0; right: 0; display: flex; gap: 8px; z-index: 10;'
          },
          [
            button(
              classes: 'nav-pill',
              attributes: const {
                'style': 'margin-bottom: 0; padding: 4px 10px; font-size: 11px; font-weight: bold; cursor: pointer;'
              },
              events: {'click': (e) => setState(() => _fontSize = (_fontSize > 10) ? _fontSize - 2 : 10)},
              [Component.text('A-')],
            ),
            button(
              classes: 'nav-pill',
              attributes: const {
                'style': 'margin-bottom: 0; padding: 4px 10px; font-size: 11px; font-weight: bold; cursor: pointer;'
              },
              events: {'click': (e) => setState(() => _fontSize = (_fontSize < 48) ? _fontSize + 2 : 48)},
              [Component.text('A+')],
            ),
          ],
        ),
        div(
          attributes: const {
            'style': 'margin-top: 36px; width: 100%; box-sizing: border-box; overflow: visible;'
          },
          [
            if (_loading)
              div(classes: 'flex-col gap-2 py-4', [
                div(classes: 'skeleton-line shimmer-bg', []),
                div(classes: 'skeleton-line medium shimmer-bg', []),
              ])
            else
              div(
                _renderLines(_content),
                attributes: const {'style': 'width: 100%; overflow: visible; display: block;'},
              )
          ],
        )
      ],
    );
  }
}

/// Dedicated desktop 3rd column (bonusColumn) text reader.
/// Clean card presentation rendered inside MultiPageColumnLayout.
class TextReaderColumnPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;

  const TextReaderColumnPanel({
    required this.imageId,
    this.fanzineId,
    super.key,
  });

  @override
  State<TextReaderColumnPanel> createState() => _TextReaderColumnPanelState();
}

class _TextReaderColumnPanelState extends State<TextReaderColumnPanel> {
  String _content = "Loading digitized text...";
  bool _loading = true;
  Map<String, Map<String, dynamic>> _loadedProfiles = {};

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _fetchText();
    }
  }

  @override
  void didUpdateComponent(TextReaderColumnPanel oldComponent) {
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

    setState(() => _loading = true);
    try {
      final res = await fsGetDoc('images/${component.imageId}');
      final doc = jsonDecode(res);
      if (doc['exists'] && mounted) {
        final data = doc['data'];
        final String? textVal = data['text_linked'] ??
            data['text_corrected'] ??
            data['text_raw'] ??
            data['text'];
        final resolvedText = (textVal != null && textVal.trim().isNotEmpty)
            ? textVal
            : "Transcription pending for this page.";
        final String fullyResolvedText = await resolveAndReplaceShortcodes(
          component.fanzineId ?? '',
          resolvedText,
        );
        setState(() {
          _content = fullyResolvedText;
          _loading = false;
        });
        _loadProfiles(fullyResolvedText);
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

  Future<void> _loadProfiles(String textContent) async {
    final regex = RegExp(r'\[\[(.*?)\]\]');
    final matches = regex.allMatches(textContent);
    final Set<String> uidsToFetch = {};

    for (final m in matches) {
      final content = m.group(1) ?? '';
      final parts = content.split('|');
      String? ref;
      if (parts.length == 2 && parts[1].contains(':')) {
        ref = parts[1].trim();
      } else if (parts.length >= 3) {
        ref = parts[2].trim();
      }
      if (ref != null && ref.startsWith('user:')) {
        final uid = ref.substring(5);
        if (!_loadedProfiles.containsKey(uid)) {
          uidsToFetch.add(uid);
        }
      }
    }

    if (uidsToFetch.isEmpty) return;

    final Map<String, Map<String, dynamic>> fetchedProfiles = {};
    for (var uid in uidsToFetch) {
      try {
        final res = await fsGetDoc('profiles/$uid');
        final doc = jsonDecode(res);
        if (doc['exists'] == true) {
          fetchedProfiles[uid] = doc['data'] as Map<String, dynamic>;
        }
      } catch (_) {}
    }

    if (mounted && fetchedProfiles.isNotEmpty) {
      setState(() {
        _loadedProfiles.addAll(fetchedProfiles);
      });
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return div(classes: 'flex-col gap-2 py-4', [
        div(classes: 'skeleton-line shimmer-bg', []),
        div(classes: 'skeleton-line medium shimmer-bg', []),
      ]);
    }

    return div(
      [
        p(
          renderWikilinkSpans(_content, _loadedProfiles, context),
          attributes: const {
            'style': 'font-size: 14px; font-family: Arial, Helvetica, sans-serif; line-height: 1.6; color: #1e293b; text-align: justify; margin: 0; white-space: pre-line;'
          },
        )
      ],
      attributes: const {'style': 'width: 100%; box-sizing: border-box;'},
    );
  }
}

/// Backwards-compatible alias for the default row panel
typedef TextReaderPanel = TextReaderRowPanel;