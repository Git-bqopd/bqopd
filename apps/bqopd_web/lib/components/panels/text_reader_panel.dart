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

        // Pre-process any image shortcodes into their absolute URLs before parsing
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
    final regex = RegExp(r'\[\[(.*?)\]\]');
    int currentIndex = 0;
    final matches = regex.allMatches(textContent);

    for (final match in matches) {
      // Add standard text leading up to the entity match
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
          final profile = _loadedProfiles[uid];
          final String? username = profile?['username'];
          if (profile != null && username != null && username.isNotEmpty) {
            // Rule 1: Connected to an @username handle -> Clickable link and BLACK in Impact using /@username
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
                [Component.text(display)]
            ));
          } else {
            // Rule 2: Connected to a profile ID but NO handle -> Regular weight, NOT underlined in Impact (black)
            children.add(span(
                attributes: const {
                  'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: none; color: black; cursor: default;'
                },
                [Component.text(display)]
            ));
          }
        } else if (ref.startsWith('address:')) {
          // Places / Normalized addresses linking -> Style in green with Map launcher link
          final addressVal = ref.substring(8);
          final encodedAddr = Uri.encodeComponent(addressVal);
          children.add(a(
              href: 'https://www.google.com/maps/search/?api=1&query=$encodedAddr',
              attributes: const {
                'target': '_blank',
                'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: underline; color: #16a34a; cursor: pointer; display: inline-flex; align-items: center; gap: 2px;'
              },
              [
                span([text('pin_drop')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px; margin-right: 2px; vertical-align: middle; display: inline-block;'}),
                Component.text(display)
              ]
          ));
        } else {
          // General unlinked target formatting in Impact (black)
          children.add(span(
              attributes: const {
                'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: none; color: black; cursor: default;'
              },
              [Component.text(display)]
          ));
        }
      } else {
        // Rule 3: Unlinked standard brackets -> Regular weight, NOT underlined, NOT a link in Impact (black)
        children.add(span(
            attributes: const {
              'style': 'font-family: Impact, Charcoal, "Arial Black", sans-serif; font-weight: normal; text-decoration: none; color: black; cursor: default;'
            },
            [Component.text(display)]
        ));
      }

      currentIndex = match.end;
    }

    // Add remaining plain text trailing after final entity
    if (currentIndex < textContent.length) {
      children.add(Component.text(textContent.substring(currentIndex)));
    }

    return children;
  }

  List<Component> _renderLines(String textContent) {
    final lines = textContent.split('\n');
    final List<Component> lineComponents = [];

    // Core layout processing match regular expressions
    final imageRegex = RegExp(r'^\{\{IMAGE(?::\s*(.*?))?\}\}$', caseSensitive: false);
    final headerRegex = RegExp(r'^(#{1,6})\s+(.*)$');
    final templateRegex = RegExp(r'^\{\{TEMPLATE_(\d+):\s*([^|]+)\s*\|\s*(.*?)\}\}$', caseSensitive: false);
    final colBreakRegex = RegExp(r'^(?:\{\{|\[\[)COLUMN_BREAK(?:\}\}|\]\])$', caseSensitive: false);

    int currentRow = 0;

    for (var line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) {
        lineComponents.add(div([], attributes: const {'style': 'height: 16px;'}));
        continue;
      }

      final imageMatch = imageRegex.firstMatch(cleanLine);
      final headerMatch = headerRegex.firstMatch(cleanLine);
      final templateMatch = templateRegex.firstMatch(cleanLine);
      final colBreakMatch = colBreakRegex.firstMatch(cleanLine);

      if (colBreakMatch != null || cleanLine == 'column-break' || cleanLine == 'column_break') {
        // Render a soft divider on column breaks
        lineComponents.add(
            div(
              attributes: const {
                'style': 'height: 1px; background: linear-gradient(to right, transparent, #cbd5e1, transparent); margin: 32px 0;'
              },
              [],
            )
        );
        currentRow = 0;
      } else if (templateMatch != null) {
        final templateNum = templateMatch.group(1) ?? '1';
        final url = templateMatch.group(2)?.trim() ?? '';
        final restContent = templateMatch.group(3)?.trim() ?? '';

        String caption = restContent;
        int? targetRow;

        final rowMatch = RegExp(r'^row=(\d+)\s*\|\s*(.*)$', caseSensitive: false).firstMatch(restContent);
        if (rowMatch != null) {
          targetRow = int.tryParse(rowMatch.group(1) ?? '');
          caption = rowMatch.group(2)!.trim();
        }

        if (templateNum == '1') {
          final int imgRows = 8;
          final int captionRows = (caption.length / 60).ceil();

          if (targetRow != null) {
            final int targetTopRow = targetRow - imgRows;
            if (currentRow < targetTopRow) {
              final int blankRows = targetTopRow - currentRow;
              lineComponents.add(
                  div(
                    attributes: {
                      'style': 'height: ${blankRows * 24}px; width: 100%;'
                    },
                    [],
                  )
              );
            }
            currentRow = targetRow + captionRows;
          } else {
            currentRow += imgRows + captionRows;
          }

          lineComponents.add(
              div(
                  classes: 'my-6 flex flex-col items-stretch border border-gray-200 rounded-lg overflow-hidden bg-white shadow-sm hover:shadow-md transition-shadow duration-200',
                  attributes: const {'style': 'margin: 24px 0; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden; background-color: white; display: flex; flex-direction: column; align-items: stretch;'},
                  [
                    if (url.isNotEmpty)
                      img(
                          src: url,
                          attributes: const {'style': 'width: 100%; height: auto; object-fit: contain; max-height: 450px;'}
                      ),
                    if (caption.isNotEmpty)
                      div(
                          classes: 'p-4 bg-gray-50 border-t border-gray-150 text-center',
                          attributes: const {'style': 'padding: 16px; background-color: #f9fafb; border-top: 1px solid #f1f5f9; text-align: center;'},
                          [
                            p(
                                classes: 'text-sm text-gray-600 italic font-medium leading-relaxed m-0',
                                attributes: const {'style': 'font-size: 14px; color: #4b5563; font-style: italic; font-weight: 500; line-height: 1.625; margin: 0;'},
                                [Component.text(caption)]
                            )
                          ]
                      )
                  ]
              )
          );
        } else {
          lineComponents.add(p([Component.text('Unknown Template $templateNum: $caption')]));
        }
      } else if (imageMatch != null) {
        final url = imageMatch.group(1)?.trim();
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
        ], attributes: const {'style': 'width: 100%; text-align: center; display: block;'} ));
        currentRow += 8;
      } else if (headerMatch != null) {
        // MATCHED MARKDOWN HEADER BLOCK -> USE IMPACT
        final level = headerMatch.group(1)!.length;
        final content = headerMatch.group(2)!.trim();
        final double headerSize = _fontSize + (4.0 * (7 - level));
        final headingChildren = _parseAndRenderContent(content);

        final headingAttributes = {
          'style': 'font-size: ${headerSize}px; '
              'font-family: Impact, Charcoal, "Arial Black", sans-serif; '
              'line-height: 1.2; '
              'color: #111; '
              'margin: 20px 0 10px 0; '
              'font-weight: normal; '
              'letter-spacing: 0.5px;'
        };

        switch (level) {
          case 1:
            lineComponents.add(h1(headingChildren, attributes: headingAttributes));
            break;
          case 2:
            lineComponents.add(h2(headingChildren, attributes: headingAttributes));
            break;
          case 3:
            lineComponents.add(h3(headingChildren, attributes: headingAttributes));
            break;
          case 4:
            lineComponents.add(h4(headingChildren, attributes: headingAttributes));
            break;
          case 5:
            lineComponents.add(h5(headingChildren, attributes: headingAttributes));
            break;
          case 6:
          default:
            lineComponents.add(h6(headingChildren, attributes: headingAttributes));
            break;
        }
        currentRow += 2;
      } else {
        // STANDARD PARAGRAPH BLOCK -> USE ARIAL
        lineComponents.add(p(
            _parseAndRenderContent(cleanLine),
            attributes: {
              'style': 'font-size: ${_fontSize}px; '
                  'font-family: Arial, Helvetica, sans-serif; '
                  'line-height: 1.6; '
                  'color: #2D3748; '
                  'text-align: justify; '
                  'margin: 0 0 14px 0;'
            }
        ));
        currentRow += (cleanLine.length / 60).ceil();
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
          // Zoom scale triggers
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
                    [Component.text('A-')]
                ),
                button(
                    classes: 'nav-pill',
                    attributes: const {
                      'style': 'margin-bottom: 0; margin-left: 4px; padding: 4px 10px; font-size: 11px; font-weight: bold; cursor: pointer;'
                    },
                    events: {'click': (e) => setState(() => _fontSize = (_fontSize < 48) ? _fontSize + 2 : 48)},
                    [Component.text('A+')]
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