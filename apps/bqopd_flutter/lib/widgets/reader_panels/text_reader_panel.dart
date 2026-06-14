import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Flutter implementation of the TextReaderPanel.
/// Parses markdown wiki-links dynamically, rendering verified handles as clickable underlined texts,
/// and unlinked/unverified entities as plain bold text.
class TextReaderPanel extends StatefulWidget {
  final String text;
  final ValueNotifier<double> fontSizeNotifier;

  const TextReaderPanel({
    super.key,
    required this.text,
    required this.fontSizeNotifier,
  });

  @override
  State<TextReaderPanel> createState() => _TextReaderPanelState();
}

class _TextReaderPanelState extends State<TextReaderPanel> {
  final Map<String, Map<String, dynamic>> _loadedProfiles = {};
  bool _loadingProfiles = true;
  late String _processedText;

  @override
  void initState() {
    super.initState();
    _processedText = widget.text;
    _loadEntityProfiles();
  }

  @override
  void didUpdateWidget(covariant TextReaderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _processedText = widget.text;
      _loadEntityProfiles();
    }
  }

  Future<void> _loadEntityProfiles() async {
    final regex = RegExp(r'\[\[(.*?)\]\]');
    final matches = regex.allMatches(_processedText);
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
    if (uidsToFetch.isEmpty) {
      if (mounted) {
        setState(() {
          _loadingProfiles = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loadingProfiles = true;
      });
    }
    try {
      final List<Future<void>> fetches = [];
      final Map<String, Map<String, dynamic>> fetchedProfiles = {};
      for (var uid in uidsToFetch) {
        fetches.add(
          FirebaseFirestore.instance.collection('profiles').doc(uid).get().then((doc) {
            if (doc.exists && doc.data() != null) {
              fetchedProfiles[uid] = doc.data()!;
            }
          }).catchError((e) {
            debugPrint('Error loading profile $uid: $e');
          }),
        );
      }
      await Future.wait(fetches);
      if (mounted) {
        setState(() {
          _loadedProfiles.addAll(fetchedProfiles);
          _loadingProfiles = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching profiles: $e');
      if (mounted) {
        setState(() {
          _loadingProfiles = false;
        });
      }
    }
  }

  List<InlineSpan> _parseAndRenderContent(BuildContext context, String textContent, TextStyle baseStyle) {
    final List<InlineSpan> spans = [];
    final regex = RegExp(r'\[\[(.*?)\]\]');
    int currentIndex = 0;
    final matches = regex.allMatches(textContent);
    for (final match in matches) {
      // Add standard text leading up to the entity match
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: textContent.substring(currentIndex, match.start),
          style: baseStyle,
        ));
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

      if (ref != null && ref.startsWith('user:')) {
        final uid = ref.substring(5);
        final profile = _loadedProfiles[uid];
        final String? username = profile?['username'];
        if (profile != null && username != null && username.isNotEmpty) {
          // Rule 1: Connected to an @username handle -> Bold, Underlined, and Clickable
          spans.add(TextSpan(
            text: display,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                context.go('/$username');
              },
          ));
        } else {
          // Rule 2: Connected to profile ID but NO handle -> Bold, NOT underlined, NOT clickable
          spans.add(TextSpan(
            text: display,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ));
        }
      } else {
        // Rule 3: Unlinked standard brackets -> Bold, NOT underlined, NOT clickable
        spans.add(TextSpan(
          text: display,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ));
      }
      currentIndex = match.end;
    }
    // Add remaining plain text
    if (currentIndex < textContent.length) {
      spans.add(TextSpan(
        text: textContent.substring(currentIndex),
        style: baseStyle,
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfiles) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: CircularProgressIndicator(color: Colors.grey),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FontSizeSlider(fontSizeNotifier: widget.fontSizeNotifier),
        ValueListenableBuilder<double>(
          valueListenable: widget.fontSizeNotifier,
          builder: (context, size, _) {
            final baseStyle = TextStyle(
              fontSize: size,
              fontFamily: 'Georgia',
              height: 1.6,
              color: Colors.black87,
            );
            return SelectableText.rich(
              TextSpan(
                children: _parseAndRenderContent(context, _processedText, baseStyle),
              ),
              textAlign: TextAlign.justify,
            );
          },
        ),
      ],
    );
  }
}

class _FontSizeSlider extends StatelessWidget {
  final ValueNotifier<double> fontSizeNotifier;
  const _FontSizeSlider({required this.fontSizeNotifier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          const Icon(Icons.format_size, size: 14, color: Colors.grey),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: fontSizeNotifier,
              builder: (context, size, _) {
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.black54,
                    inactiveTrackColor: Colors.black12,
                    thumbColor: Colors.black,
                  ),
                  child: Slider(
                    value: size,
                    min: 12.0,
                    max: 48.0,
                    divisions: 36,
                    onChanged: (val) => fontSizeNotifier.value = val,
                  ),
                );
              },
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: fontSizeNotifier,
            builder: (context, size, _) => Text(
              "${size.toInt()}px",
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}