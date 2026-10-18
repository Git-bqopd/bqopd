import 'dart:convert';

/// A pure Dart utility for pre-rendering archival Markdown and Wikilinks
/// into deterministic, production-ready static HTML.
///
/// Implements the "Bake Once, Read Many" architecture: resolves user profiles,
/// Google Maps address pins, headers, lists, and image tokens into self-contained
/// HTML markup ready for zero-latency injection with `Component.raw()`.
class TextHtmlRenderer {
  /// Default body font family matching the bqopd design tokens.
  static const String kBodyFontFamily = "'Arimo', sans-serif";

  /// Default display font family for headings and entity links.
  static const String kHeadingFontFamily = "'Anton', sans-serif";

  /// Renders continuous [markdown] into pre-baked semantic HTML.
  ///
  /// - [userHandles]: Map of user UIDs or normalized names to handles (e.g. `{'uid1': 'handle'}`).
  /// - [userNames]: Optional map of user UIDs to verified display names.
  /// - [addressMap]: Optional map of raw location strings to normalized addresses or coordinates.
  /// - [userHandleResolver]: Optional callback resolving a user UID to a handle.
  /// - [addressResolver]: Optional callback resolving address strings to query parameters.
  /// - [includeWrapper]: If true, wraps the result in a styled container `<div>`.
  /// - [baseFontSize]: Font size in pixels for base paragraphs (default 15.0).
  static String renderToHtml(
      String markdown, {
        Map<String, String>? userHandles,
        Map<String, String>? userNames,
        Map<String, String>? addressMap,
        String? Function(String uid)? userHandleResolver,
        String? Function(String address)? addressResolver,
        bool includeWrapper = false,
        String wrapperClass = 'pre-rendered-text-reader',
        double baseFontSize = 15.0,
      }) {
    if (markdown.trim().isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    final lines = markdown.split('\n');

    int i = 0;
    while (i < lines.length) {
      final rawLine = lines[i];
      final trimmed = rawLine.trim();

      // 1. Skip completely empty lines
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // 2. Column Break controls
      if (_isColumnBreak(trimmed)) {
        buffer.writeln(
          '<hr class="reader-column-divider" style="border: 0; border-top: 1px dashed #cbd5e1; margin: 20px 0;" />',
        );
        i++;
        continue;
      }

      // 3. Composite Template Block: {{TEMPLATE_1: url | caption}}
      final templateMatch = _templateRegex.firstMatch(trimmed);
      if (templateMatch != null) {
        final tNum = templateMatch.group(1) ?? '1';
        final url = templateMatch.group(2)?.trim() ?? '';
        final rest = templateMatch.group(3)?.trim() ?? '';
        final caption = _extractCaptionFromTemplateParams(rest);

        buffer.writeln(
          _renderTemplateFigure(
            templateNum: tNum,
            imageUrl: url,
            caption: caption,
            userHandles: userHandles,
            userNames: userNames,
            addressMap: addressMap,
            userHandleResolver: userHandleResolver,
            addressResolver: addressResolver,
          ),
        );
        i++;
        continue;
      }

      // 4. Standalone Image Block: {{IMAGE: url | ...}}
      final imageMatch = _imageRegex.firstMatch(trimmed);
      if (imageMatch != null) {
        final rawArg = imageMatch.group(1)?.trim() ?? '';
        final parts = rawArg.split('|');
        final url = parts[0].trim();

        if (url.isNotEmpty) {
          buffer.writeln(
            '<figure class="reader-image-figure" style="margin: 16px 0; text-align: center;">'
                '<img src="${_escapeAttr(url)}" alt="Archival Plate" style="max-width: 100%; height: auto; border-radius: 4px; box-shadow: 0 1px 4px rgba(0,0,0,0.1); display: inline-block;" loading="lazy" />'
                '</figure>',
          );
        }
        i++;
        continue;
      }

      // 5. Headings: #, ##, ###, ####, #####, ######
      final headerMatch = _headerRegex.firstMatch(trimmed);
      if (headerMatch != null) {
        final level = headerMatch.group(1)!.length;
        final rawContent = headerMatch.group(2)!.trim();
        final contentHtml = _renderInline(
          rawContent,
          userHandles: userHandles,
          userNames: userNames,
          addressMap: addressMap,
          userHandleResolver: userHandleResolver,
          addressResolver: addressResolver,
        );

        buffer.writeln(_buildHeadingTag(level, contentHtml, baseFontSize));
        i++;
        continue;
      }

      // 6. Horizontal Rules (---, ***, ___)
      if (_hrRegex.hasMatch(trimmed)) {
        buffer.writeln(
          '<hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 20px 0;" />',
        );
        i++;
        continue;
      }

      // 7. Bullet Lists (* item, - item)
      if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
        buffer.writeln(
          '<ul style="font-family: $kBodyFontFamily; font-size: ${baseFontSize}px; line-height: 1.6; color: #2d3748; margin: 0 0 14px 0; padding-left: 22px;">',
        );
        while (i < lines.length &&
            (lines[i].trim().startsWith('* ') || lines[i].trim().startsWith('- '))) {
          final itemText = lines[i].trim().substring(2).trim();
          final itemHtml = _renderInline(
            itemText,
            userHandles: userHandles,
            userNames: userNames,
            addressMap: addressMap,
            userHandleResolver: userHandleResolver,
            addressResolver: addressResolver,
          );
          buffer.writeln('  <li style="margin-bottom: 4px;">$itemHtml</li>');
          i++;
        }
        buffer.writeln('</ul>');
        continue;
      }

      // 8. Numbered Lists (1. item, 2. item)
      if (_numberedListRegex.hasMatch(trimmed)) {
        buffer.writeln(
          '<ol style="font-family: $kBodyFontFamily; font-size: ${baseFontSize}px; line-height: 1.6; color: #2d3748; margin: 0 0 14px 0; padding-left: 22px;">',
        );
        while (i < lines.length && _numberedListRegex.hasMatch(lines[i].trim())) {
          final match = _numberedListRegex.firstMatch(lines[i].trim())!;
          final itemText = lines[i].trim().substring(match.group(0)!.length).trim();
          final itemHtml = _renderInline(
            itemText,
            userHandles: userHandles,
            userNames: userNames,
            addressMap: addressMap,
            userHandleResolver: userHandleResolver,
            addressResolver: addressResolver,
          );
          buffer.writeln('  <li style="margin-bottom: 4px;">$itemHtml</li>');
          i++;
        }
        buffer.writeln('</ol>');
        continue;
      }

      // 9. Standard Text Paragraph (coalesces wrapped consecutive lines)
      final paragraphLines = <String>[];
      while (i < lines.length) {
        final currentTrim = lines[i].trim();
        if (currentTrim.isEmpty ||
            _isSpecialBlockStart(currentTrim)) {
          break;
        }
        paragraphLines.add(currentTrim);
        i++;
      }

      if (paragraphLines.isNotEmpty) {
        final combinedText = paragraphLines.join(' ');
        final contentHtml = _renderInline(
          combinedText,
          userHandles: userHandles,
          userNames: userNames,
          addressMap: addressMap,
          userHandleResolver: userHandleResolver,
          addressResolver: addressResolver,
        );

        buffer.writeln(
          '<p style="font-family: $kBodyFontFamily; font-size: ${baseFontSize}px; line-height: 1.6; color: #2d3748; text-align: justify; margin: 0 0 14px 0; word-break: break-word;">'
              '$contentHtml'
              '</p>',
        );
      }
    }

    final rawHtml = buffer.toString().trim();

    if (includeWrapper) {
      return '<div class="$wrapperClass" style="font-family: $kBodyFontFamily; font-size: ${baseFontSize}px; line-height: 1.6; color: #2d3748; width: 100%; box-sizing: border-box;">\n'
          '$rawHtml\n'
          '</div>';
    }

    return rawHtml;
  }

  /// Transforms inline formatting (wikilinks, markdown links, bold, italic, code)
  /// while escaping raw text content against HTML injection.
  static String _renderInline(
      String text, {
        Map<String, String>? userHandles,
        Map<String, String>? userNames,
        Map<String, String>? addressMap,
        String? Function(String uid)? userHandleResolver,
        String? Function(String address)? addressResolver,
      }) {
    if (text.isEmpty) return '';

    final tokens = _tokenizeInline(text);
    final buffer = StringBuffer();

    for (final token in tokens) {
      switch (token.type) {
        case _TokenType.plainText:
          buffer.write(_renderMarkdownStyles(htmlEscape.convert(token.content)));
          break;

        case _TokenType.wikilink:
          buffer.write(
            _renderWikilink(
              token.content,
              userHandles: userHandles,
              userNames: userNames,
              addressMap: addressMap,
              userHandleResolver: userHandleResolver,
              addressResolver: addressResolver,
            ),
          );
          break;

        case _TokenType.markdownLink:
          buffer.write(
            _renderStandardLink(token.label ?? '', token.url ?? ''),
          );
          break;
      }
    }

    return buffer.toString();
  }

  /// Transforms a single wikilink `[[Content]]` into an active semantic anchor or badge.
  static String _renderWikilink(
      String content, {
        Map<String, String>? userHandles,
        Map<String, String>? userNames,
        Map<String, String>? addressMap,
        String? Function(String uid)? userHandleResolver,
        String? Function(String address)? addressResolver,
      }) {
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

    final escapedDisplay = htmlEscape.convert(display);

    // 1. Explicit Address Reference: [[Location|address:43.83,-91.24]]
    if (ref != null && ref.startsWith('address:')) {
      final rawAddress = ref.substring(8).trim();
      final resolvedAddress = addressResolver?.call(rawAddress) ??
          addressMap?[rawAddress] ??
          rawAddress;
      final encodedQuery = Uri.encodeComponent(resolvedAddress);
      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$encodedQuery';

      return '<a href="$mapsUrl" target="_blank" rel="noopener noreferrer" class="wikilink-address" '
          'style="font-family: $kHeadingFontFamily; font-weight: normal; text-decoration: underline; color: #16a34a; cursor: pointer; display: inline-flex; align-items: baseline; gap: 2px;">'
          '<span style="font-size: 0.9em; vertical-align: middle;">📍</span>$escapedDisplay'
          '</a>';
    }

    // 2. Explicit User Reference: [[Name|user:UID]]
    if (ref != null && ref.startsWith('user:')) {
      final uid = ref.substring(5).trim();
      final handle = userHandleResolver?.call(uid) ??
          userHandles?[uid] ??
          _lookupHandleByName(display, userHandles);

      if (handle != null && handle.isNotEmpty) {
        final cleanHandle = handle.replaceAll('@', '').trim();
        return '<a href="/@$cleanHandle" class="wikilink-user" '
            'style="font-family: $kHeadingFontFamily; font-weight: normal; text-decoration: underline; color: #111827; cursor: pointer;">'
            '$escapedDisplay'
            '</a>';
      }

      // Fallback if handle is unknown for this UID
      return '<span class="wikilink-user-unresolved" '
          'style="font-family: $kHeadingFontFamily; font-weight: normal; text-decoration: none; color: #111827;">'
          '$escapedDisplay'
          '</span>';
    }

    // 3. Shorthand Handle: [[@username]]
    if (display.startsWith('@')) {
      final cleanHandle = display.substring(1).trim();
      return '<a href="/@$cleanHandle" class="wikilink-user" '
          'style="font-family: $kHeadingFontFamily; font-weight: normal; text-decoration: underline; color: #111827; cursor: pointer;">'
          '$escapedDisplay'
          '</a>';
    }

    // 4. Shorthand Name matching a known user handle map: [[Name]]
    final matchedHandle = _lookupHandleByName(display, userHandles);
    if (matchedHandle != null && matchedHandle.isNotEmpty) {
      final cleanHandle = matchedHandle.replaceAll('@', '').trim();
      return '<a href="/@$cleanHandle" class="wikilink-user" '
          'style="font-family: $kHeadingFontFamily; font-weight: normal; text-decoration: underline; color: #111827; cursor: pointer;">'
          '$escapedDisplay'
          '</a>';
    }

    // 5. Unresolved plain entity
    return '<span class="wikilink-unresolved" '
        'style="font-family: $kHeadingFontFamily; font-weight: normal; text-decoration: none; color: #111827;">'
        '$escapedDisplay'
        '</span>';
  }

  /// Renders standard markdown links `[label](url)` as HTML `<a>` tags.
  static String _renderStandardLink(String label, String url) {
    final escapedLabel = htmlEscape.convert(label);
    final escapedUrl = _escapeAttr(url);

    return '<a href="$escapedUrl" target="_blank" rel="noopener noreferrer" class="reader-external-link" '
        'style="color: #6750A4; text-decoration: underline; font-weight: 500;">'
        '$escapedLabel'
        '</a>';
  }

  /// Parses inline bold, italic, strikethrough, and monospace code.
  static String _renderMarkdownStyles(String escapedHtml) {
    var result = escapedHtml;

    // Code `code`
    result = result.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) {
      return '<code style="font-family: monospace; background: #f1f5f9; padding: 2px 4px; border-radius: 4px; font-size: 0.9em; color: #0f172a;">${m.group(1)}</code>';
    });

    // Bold **text** or __text__
    result = result.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) {
      return '<strong>${m.group(1)}</strong>';
    });
    result = result.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) {
      return '<strong>${m.group(1)}</strong>';
    });

    // Italic *text* or _text_
    result = result.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) {
      return '<em>${m.group(1)}</em>';
    });
    result = result.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) {
      return '<em>${m.group(1)}</em>';
    });

    // Strikethrough ~~text~~
    result = result.replaceAllMapped(RegExp(r'~~([^~]+)~~'), (m) {
      return '<del>${m.group(1)}</del>';
    });

    return result;
  }

  /// Constructs semantic heading tags using the Anton display font family.
  static String _buildHeadingTag(int level, String contentHtml, double baseSize) {
    final double fontSize = switch (level) {
      1 => baseSize + 16.0, // ~31px
      2 => baseSize + 11.0, // ~26px
      3 => baseSize + 6.0,  // ~21px
      4 => baseSize + 3.0,  // ~18px
      _ => baseSize + 1.0,  // ~16px
    };

    final topMargin = switch (level) {
      1 => 20,
      2 => 16,
      3 => 14,
      _ => 12,
    };

    return '<h$level style="font-family: $kHeadingFontFamily; font-size: ${fontSize.toStringAsFixed(1)}px; '
        'line-height: 1.2; color: #111827; margin: ${topMargin}px 0 8px 0; font-weight: normal; '
        'text-transform: uppercase; letter-spacing: 0.5px;">'
        '$contentHtml'
        '</h$level>';
  }

  /// Renders a composite template figure with image and formatted caption.
  static String _renderTemplateFigure({
    required String templateNum,
    required String imageUrl,
    required String caption,
    Map<String, String>? userHandles,
    Map<String, String>? userNames,
    Map<String, String>? addressMap,
    String? Function(String uid)? userHandleResolver,
    String? Function(String address)? addressResolver,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<figure class="reader-template-figure" style="margin: 18px 0; text-align: center;">');

    if (imageUrl.isNotEmpty) {
      buffer.writeln(
        '  <img src="${_escapeAttr(imageUrl)}" alt="Template $templateNum Illustration" '
            'style="max-width: 100%; height: auto; border-radius: 4px; box-shadow: 0 1px 4px rgba(0,0,0,0.1); display: inline-block;" loading="lazy" />',
      );
    }

    if (caption.isNotEmpty) {
      final captionHtml = _renderInline(
        caption,
        userHandles: userHandles,
        userNames: userNames,
        addressMap: addressMap,
        userHandleResolver: userHandleResolver,
        addressResolver: addressResolver,
      );
      buffer.writeln(
        '  <figcaption style="font-family: $kBodyFontFamily; font-size: 13px; font-style: italic; color: #64748b; margin-top: 8px; line-height: 1.4;">'
            '$captionHtml'
            '</figcaption>',
      );
    }

    buffer.writeln('</figure>');
    return buffer.toString();
  }

  static final RegExp _headerRegex = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _numberedListRegex = RegExp(r'^\d+\.\s+');
  static final RegExp _hrRegex = RegExp(r'^(?:-{3,}|\*{3,}|_{3,})$');
  static final RegExp _imageRegex =
  RegExp(r'^(?:\{\{|\[\[)IMAGE(?::\s*(.*?))?(?:\}\}|\]\])$', caseSensitive: false);
  static final RegExp _templateRegex = RegExp(
    r'^(?:\{\{|\[\[)TEMPLATE_(\d+):\s*([^|]+)\s*\|\s*(.*?)(?:\}\}|\]\])$',
    caseSensitive: false,
  );
  static final RegExp _columnBreakRegex =
  RegExp(r'^(?:\{\{|\[\[)COLUMN_BREAK(?:\}\}|\]\])$', caseSensitive: false);

  static bool _isColumnBreak(String line) {
    if (_columnBreakRegex.hasMatch(line)) return true;
    final lower = line.toLowerCase();
    return lower == 'column-break' || lower == 'column_break';
  }

  static bool _isSpecialBlockStart(String line) {
    return _headerRegex.hasMatch(line) ||
        line.startsWith('* ') ||
        line.startsWith('- ') ||
        _numberedListRegex.hasMatch(line) ||
        _isColumnBreak(line) ||
        _imageRegex.hasMatch(line) ||
        _templateRegex.hasMatch(line) ||
        _hrRegex.hasMatch(line);
  }

  static String _extractCaptionFromTemplateParams(String rawRest) {
    final rowMatch = RegExp(r'^row=\d+\s*\|\s*(.*)$', caseSensitive: false).firstMatch(rawRest);
    if (rowMatch != null) {
      return rowMatch.group(1)?.trim() ?? '';
    }
    return rawRest.trim();
  }

  static String? _lookupHandleByName(String name, Map<String, String>? userHandles) {
    if (userHandles == null || userHandles.isEmpty) return null;
    if (userHandles.containsKey(name)) return userHandles[name];
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (userHandles.containsKey(normalized)) return userHandles[normalized];
    return null;
  }

  static String _escapeAttr(String url) {
    return url.replaceAll('"', '&quot;').replaceAll("'", '&#39;');
  }

  static List<_InlineToken> _tokenizeInline(String text) {
    final List<_InlineToken> tokens = [];
    final pattern = RegExp(r'(\[\[.*?\]\])|(\[.*?\]\(.*?\))');
    int currentIndex = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > currentIndex) {
        tokens.add(_InlineToken.plain(text.substring(currentIndex, match.start)));
      }

      final matchedStr = match.group(0)!;
      if (matchedStr.startsWith('[[') && matchedStr.endsWith(']]')) {
        tokens.add(
          _InlineToken.wikilink(matchedStr.substring(2, matchedStr.length - 2)),
        );
      } else if (matchedStr.startsWith('[') && matchedStr.contains('](')) {
        final closeBracket = matchedStr.indexOf('](');
        final label = matchedStr.substring(1, closeBracket);
        final url = matchedStr.substring(closeBracket + 2, matchedStr.length - 1);
        tokens.add(_InlineToken.markdownLink(label: label, url: url));
      }

      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      tokens.add(_InlineToken.plain(text.substring(currentIndex)));
    }

    return tokens;
  }
}

enum _TokenType { plainText, wikilink, markdownLink }

class _InlineToken {
  final _TokenType type;
  final String content;
  final String? label;
  final String? url;

  _InlineToken.plain(this.content)
      : type = _TokenType.plainText,
        label = null,
        url = null;

  _InlineToken.wikilink(this.content)
      : type = _TokenType.wikilink,
        label = null,
        url = null;

  _InlineToken.markdownLink({required this.label, required this.url})
      : type = _TokenType.markdownLink,
        content = '';
}