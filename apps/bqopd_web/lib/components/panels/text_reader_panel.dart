import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/firebase_mocks.dart';

/// Renders page text with dynamic parser support for Wiki-Link entities.
/// Renders verified usernames as clickable links, and unlinked entities as plain bold text.
class TextReaderPanel extends StatefulComponent {
  final String imageId;
  final String? fanzineId;

  const TextReaderPanel({required this.imageId, this.fanzineId, super.key});

  @override
  State<TextReaderPanel> createState() => _TextReaderPanelState();
}

class _TextReaderPanelState extends State<TextReaderPanel> {
  String _content = "Loading digitized text...";
  double _fontSize = 16.0;
  bool _loading = true; // High-fidelity state tracking
  Map<String, Map<String, dynamic>> _loadedProfiles = {};

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

        // Match the Gold Master fallback hierarchy
        final String? textVal = data['text_linked'] ??
            data['text_corrected'] ??
            data['text_raw'] ??
            data['text']; // Legacy fallback

        final resolvedText = (textVal != null && textVal.trim().isNotEmpty)
            ? textVal
            : "Transcription pending for this page.";

        // Pre-process any image shortcodes into their absolute URLs before parsing!
        final String fullyResolvedText = await resolveAndReplaceShortcodes(
          component.fanzineId ?? '',
          resolvedText,
        );

        setState(() {
          _content = fullyResolvedText;
          _loading = false;
        });

        // Trigger loading profiles for entities in the background
        _loadEntityProfiles(fullyResolvedText);
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

  Future<void> _loadEntityProfiles(String textContent) async {
    final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
    final matches = regex.allMatches(textContent);
    final Set<String> uidsToFetch = {};

    for (final m in matches) {
      final ref = m.group(2)?.trim();
      if (ref != null && ref.startsWith('user:')) {
        final uid = ref.substring(5);
        if (!_loadedProfiles.containsKey(uid)) {
          uidsToFetch.add(uid);
        }
      }
    }

    if (uidsToFetch.isEmpty) return;

    final List<Future<void>> fetches = [];
    final Map<String, Map<String, dynamic>> fetchedProfiles = {};

    for (var uid in uidsToFetch) {
      fetches.add(
          fsGetDoc('profiles/$uid').then((res) {
            final doc = jsonDecode(res);
            if (doc['exists'] == true) {
              fetchedProfiles[uid] = doc['data'] as Map<String, dynamic>;
            }
          }).catchError((e) {
            print('[TEXT READER PANEL] Error loading profile $uid: $e');
          })
      );
    }

    if (fetches.isNotEmpty) {
      await Future.wait(fetches);
      if (mounted) {
        setState(() {
          _loadedProfiles.addAll(fetchedProfiles);
        });
      }
    }
  }

  List<Component> _parseAndRenderContent(String textContent) {
    final List<Component> children = [];
    final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');

    int currentIndex = 0;
    final matches = regex.allMatches(textContent);

    for (final match in matches) {
      // Add standard text leading up to the entity match
      if (match.start > currentIndex) {
        children.add(text(textContent.substring(currentIndex, match.start)));
      }

      final String display = match.group(1)?.trim() ?? '';
      final String? ref = match.group(2)?.trim();

      if (ref != null && ref.startsWith('user:')) {
        final uid = ref.substring(5);
        final profile = _loadedProfiles[uid];
        final String? username = profile?['username'];

        if (profile != null && username != null && username.isNotEmpty) {
          // Rule 1: Connected to an @username handle -> Bold, Underlined, and Clickable
          children.add(a(
              href: '/$username',
              attributes: {
                'style': 'font-weight: bold; text-decoration: underline; color: #3f51b5; cursor: pointer;'
              },
              events: {
                'click': (e) {
                  e.preventDefault();
                  Router.of(context).push('/$username');
                }
              },
              [text(display)]
          ));
        } else {
          // Rule 2: Connected to a profile ID but NO handle -> Bold, NOT underlined, NOT a link
          children.add(span(
              attributes: const {
                'style': 'font-weight: bold; text-decoration: none; color: inherit; cursor: default;'
              },
              [text(display)]
          ));
        }
      } else {
        // Rule 3: Unlinked standard brackets -> Bold, NOT underlined, NOT a link
        children.add(span(
            attributes: const {
              'style': 'font-weight: bold; text-decoration: none; color: inherit; cursor: default;'
            },
            [text(display)]
        ));
      }

      currentIndex = match.end;
    }

    // Add remaining plain text trailing after final entity
    if (currentIndex < textContent.length) {
      children.add(text(textContent.substring(currentIndex)));
    }

    return children;
  }

  List<Component> _renderLines(String textContent) {
    final lines = textContent.split('\n');
    final List<Component> lineComponents = [];

    for (var line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) {
        lineComponents.add(div([], attributes: const {'style': 'height: 16px;'}));
        continue;
      }

      // Check if it's an image block: {{IMAGE: url}}
      final imageRegex = RegExp(r'^\{\{IMAGE(?::\s*(.*?))?\}\}$', caseSensitive: false);
      final match = imageRegex.firstMatch(cleanLine);

      if (match != null) {
        final url = match.group(1)?.trim();
        final finalUrl = (url != null && url.isNotEmpty) ? url : 'https://placehold.co/600x400/png?text=Image+Asset';

        lineComponents.add(div([
          img(
              src: finalUrl,
              attributes: const {
                'style': 'max-width: 100%; height: auto; margin: 16px auto; '
                    'display: block; border: 1px solid #e2e8f0; border-radius: 8px; '
                    'box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -1px rgba(0,0,0,0.06);'
              }
          )
        ], attributes: const {'style': 'width: 100%; text-align: center; display: block;'}));
      } else {
        // Render as standard paragraph line with inline wiki-linked text parsed
        lineComponents.add(p(
            _parseAndRenderContent(line),
            attributes: {
              'style': 'font-size: ${_fontSize}px; font-family: Georgia, serif; line-height: 1.6; color: #333; text-align: justify; margin: 0 0 12px 0;'
            }
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
          // Move A- and A+ buttons to the top right corner
          div(
              classes: 'flex-row gap-2',
              attributes: const {
                'style': 'position: absolute; top: 0; right: 0; display: flex; gap: 8px; z-index: 10;'
              },
              [
                button(
                    classes: 'nav-pill',
                    attributes: const {
                      'style': 'margin-bottom: 0; margin-left: 4px; padding: 4px 10px; font-size: 11px; font-weight: bold; cursor: pointer;'
                    },
                    events: {'click': (e) => setState(() => _fontSize = (_fontSize > 10) ? _fontSize - 2 : 10)},
                    [text('A-')]
                ),
                button(
                    classes: 'nav-pill',
                    attributes: const {
                      'style': 'margin-bottom: 0; margin-left: 4px; padding: 4px 10px; font-size: 11px; font-weight: bold; cursor: pointer;'
                    },
                    events: {'click': (e) => setState(() => _fontSize = (_fontSize < 48) ? _fontSize + 2 : 48)},
                    [text('A+')]
                ),
              ]
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
                    div(classes: 'skeleton-line shimmer-bg', []),
                    div(classes: 'skeleton-line short shimmer-bg', []),
                  ])
                else
                  div(
                      _renderLines(_content),
                      attributes: const {'style': 'width: 100%; overflow: visible; display: block;'}
                  )
              ]
          )
        ]
    );
  }
}