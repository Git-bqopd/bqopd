import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LinkParser {
  // Regex for [[Display Text|ID]] OR [[Display Text]]
  static final RegExp _wikiLinkRegex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
  static final RegExp _headerRegex =
      RegExp(r'^(#{1,6})\s+(.*)$', multiLine: true);

  /// Parses text for [[Shortcode]] and resolves them to database references.
  static Future<List<String>> parseMentions(String text) async {
    final Set<String> mentions = {};
    final matches = _wikiLinkRegex.allMatches(text);
    final db = FirebaseFirestore.instance;

    for (final match in matches) {
      String display = match.group(1) ?? '';
      String? explicitId = match.group(2);

      if (explicitId != null && explicitId.isNotEmpty) {
        mentions.add(explicitId);
        continue;
      }

      String code = display;
      if (code.isEmpty) continue;

      // Try to resolve username/alias
      String handleCandidate = code.toLowerCase();
      var userDoc = await db.collection('usernames').doc(handleCandidate).get();

      // FALLBACK: If "the comet" fails, try "the-comet"
      if (!userDoc.exists) {
        final hyphenated = handleCandidate.replaceAll(' ', '-');
        if (hyphenated != handleCandidate) {
          userDoc = await db.collection('usernames').doc(hyphenated).get();
        }
      }

      if (userDoc.exists) {
        final data = userDoc.data()!;
        if (data.containsKey('redirect')) {
          final targetHandle = data['redirect'];
          final targetDoc =
              await db.collection('usernames').doc(targetHandle).get();
          if (targetDoc.exists) {
            mentions.add('user:${targetDoc.data()!['uid']}');
          }
        } else {
          mentions.add('user:${data['uid']}');
        }
      }
    }
    return mentions.toList();
  }

  static TextSpan renderLinks(
    BuildContext context,
    String text, {
    TextStyle? baseStyle,
    TextStyle? linkStyle,
    TextStyle? headerStyle,
  }) {
    final List<InlineSpan> spans = [];
    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      final headerMatch = _headerRegex.firstMatch(line);

      if (headerMatch != null) {
        final content = headerMatch.group(2) ?? '';
        final level = headerMatch.group(1)?.length ?? 1;
        final double fontSize =
            (baseStyle?.fontSize ?? 16.0) + (4.0 * (6 - level));

        spans.add(TextSpan(
          children: _parseLineForLinks(
              context,
              content,
              baseStyle?.copyWith(
                      fontSize: fontSize, fontWeight: FontWeight.bold) ??
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
              linkStyle),
        ));
        spans.add(const TextSpan(text: '\n'));
      } else {
        spans.add(TextSpan(
          children: _parseLineForLinks(context, line, baseStyle, linkStyle),
        ));
        if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: spans);
  }

  static List<InlineSpan> _parseLineForLinks(BuildContext context,
      String lineText, TextStyle? style, TextStyle? linkStyle) {
    final List<InlineSpan> spans = [];
    int currentIndex = 0;
    final matches = _wikiLinkRegex.allMatches(lineText);

    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: lineText.substring(currentIndex, match.start),
          style: style,
        ));
      }

      final String display = match.group(1) ?? '';
      final String? ref = match.group(2);

      spans.add(TextSpan(
        text: display,
        style: linkStyle ??
            const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _handleLinkTap(context, ref ?? display),
      ));

      currentIndex = match.end;
    }

    if (currentIndex < lineText.length) {
      spans.add(TextSpan(
        text: lineText.substring(currentIndex),
        style: style,
      ));
    }
    return spans;
  }

  static Future<void> _handleLinkTap(BuildContext context, String ref) async {
    if (ref.contains(':')) {
      final parts = ref.split(':');
      final type = parts[0];
      final id = parts[1];

      if (type == 'user') {
        final userDoc =
            await FirebaseFirestore.instance.collection('Users').doc(id).get();
        if (userDoc.exists) {
          final username = userDoc.data()?['username'];
          if (username != null) {
            if (!context.mounted) return;
            context.go('/$username');
            return;
          }
        }
        if (!context.mounted) return;
        context.pushNamed('editInfo', queryParameters: {'userId': id});
      } else if (type == 'fanzine') {
        context.push('/reader/$id');
      }
    } else {
      final handle = ref.toLowerCase().replaceAll(' ', '-');
      context.push('/$handle');
    }
  }
}
