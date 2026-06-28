import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkParser {
  static final RegExp _wikiLinkRegex = RegExp(r'\[\[(.*?)\]\]');
  static final RegExp _headerRegex = RegExp(r'^(#{1,6})\s+(.*)$', multiLine: true);

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
        final double fontSize = (baseStyle?.fontSize ?? 16.0) + (4.0 * (6 - level));
        spans.add(TextSpan(
          children: _parseLineForLinks(
              context,
              content,
              baseStyle?.copyWith(fontSize: fontSize, fontWeight: FontWeight.bold) ??
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

  static List<InlineSpan> _parseLineForLinks(BuildContext context, String lineText, TextStyle? style, TextStyle? linkStyle) {
    final List<InlineSpan> spans = [];
    int currentIndex = 0;
    final matches = _wikiLinkRegex.allMatches(lineText);
    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: lineText.substring(currentIndex, match.start), style: style));
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

      spans.add(TextSpan(
        text: display,
        style: linkStyle ?? const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => _handleLinkTap(context, ref ?? display),
      ));
      currentIndex = match.end;
    }
    if (currentIndex < lineText.length) {
      spans.add(TextSpan(text: lineText.substring(currentIndex), style: style));
    }
    return spans;
  }

  static Future<void> _handleLinkTap(BuildContext context, String ref) async {
    if (ref.contains(':')) {
      final parts = ref.split(':');
      final id = parts[1];
      if (parts[0] == 'user') {
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(id).get();
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
      } else if (parts[0] == 'fanzine') {
        context.push('/reader/$id');
      } else if (parts[0] == 'address') {
        // Safe link launcher on mobile devices for addresses
        final encoded = Uri.encodeComponent(id);
        final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      }
    } else {
      context.push('/${ref.toLowerCase().replaceAll(' ', '-')}');
    }
  }
}