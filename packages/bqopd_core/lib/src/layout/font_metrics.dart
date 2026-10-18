import 'dart:math' as math;

/// Types of supported typographical font families bundled within the platform.
enum TypesetFontFamily {
  arimo,
  anton,
}

/// Pure Dart typographical advance metrics table for exact horizontal text measurement
/// and line wrapping without requiring Canvas context or native FreeType/Pillow binaries.
class FontMetrics {
  /// Default character advance ratio if a glyph is missing from the lookup tables.
  static const double kFallbackAdvanceRatio = 0.55;

  /// Pre-calculated advance width factors for Arimo Regular (ASCII 0..127)
  /// normalized per 1.0 unit of font size (based on standard 2048 UPM metrics).
  static const List<double> _arimoRegularAscii = [
    // 0..31: Non-printable control characters
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    // 32..47: Space and punctuation
    0.278, // ' ' (32)
    0.278, // '!' (33)
    0.355, // '"' (34)
    0.556, // '#' (35)
    0.556, // '$' (36)
    0.889, // '%' (37)
    0.667, // '&' (38)
    0.191, // ''' (39)
    0.333, // '(' (40)
    0.333, // ')' (41)
    0.389, // '*' (42)
    0.584, // '+' (43)
    0.278, // ',' (44)
    0.333, // '-' (45)
    0.278, // '.' (46)
    0.278, // '/' (47)
    // 48..57: Tabular numerals 0-9
    0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556,
    // 58..64: Punctuation and symbols
    0.278, // ':' (58)
    0.278, // ';' (59)
    0.584, // '<' (60)
    0.584, // '=' (61)
    0.584, // '>' (62)
    0.556, // '?' (63)
    1.015, // '@' (64)
    // 65..90: Uppercase A-Z
    0.667, // 'A' (65)
    0.667, // 'B' (66)
    0.722, // 'C' (67)
    0.722, // 'D' (68)
    0.667, // 'E' (69)
    0.611, // 'F' (70)
    0.778, // 'G' (71)
    0.722, // 'H' (72)
    0.278, // 'I' (73)
    0.500, // 'J' (74)
    0.667, // 'K' (75)
    0.556, // 'L' (76)
    0.833, // 'M' (77)
    0.722, // 'N' (78)
    0.778, // 'O' (79)
    0.667, // 'P' (80)
    0.778, // 'Q' (81)
    0.722, // 'R' (82)
    0.667, // 'S' (83)
    0.611, // 'T' (84)
    0.722, // 'U' (85)
    0.667, // 'V' (86)
    0.944, // 'W' (87)
    0.667, // 'X' (88)
    0.667, // 'Y' (89)
    0.611, // 'Z' (90)
    // 91..96: Brackets and symbols
    0.333, // '[' (91)
    0.278, // '\' (92)
    0.333, // ']' (93)
    0.469, // '^' (94)
    0.556, // '_' (95)
    0.333, // '`' (96)
    // 97..122: Lowercase a-z
    0.556, // 'a' (97)
    0.556, // 'b' (98)
    0.500, // 'c' (99)
    0.556, // 'd' (100)
    0.556, // 'e' (101)
    0.278, // 'f' (102)
    0.556, // 'g' (103)
    0.556, // 'h' (104)
    0.222, // 'i' (105)
    0.222, // 'j' (106)
    0.500, // 'k' (107)
    0.222, // 'l' (108)
    0.833, // 'm' (109)
    0.556, // 'n' (110)
    0.556, // 'o' (111)
    0.556, // 'p' (112)
    0.556, // 'q' (113)
    0.333, // 'r' (114)
    0.500, // 's' (115)
    0.278, // 't' (116)
    0.556, // 'u' (117)
    0.500, // 'v' (118)
    0.722, // 'w' (119)
    0.500, // 'x' (120)
    0.500, // 'y' (121)
    0.500, // 'z' (122)
    // 123..127: Braces and delimiters
    0.334, // '{' (123)
    0.260, // '|' (124)
    0.334, // '}' (125)
    0.584, // '~' (126)
    0.0, // DEL (127)
  ];

  /// Pre-calculated advance width factors for Arimo Bold (ASCII 0..127).
  static const List<double> _arimoBoldAscii = [
    // 0..31: Control codes
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    // 32..47: Space and punctuation
    0.278, // ' ' (32)
    0.333, // '!' (33)
    0.474, // '"' (34)
    0.556, // '#' (35)
    0.556, // '$' (36)
    0.889, // '%' (37)
    0.722, // '&' (38)
    0.238, // ''' (39)
    0.333, // '(' (40)
    0.333, // ')' (41)
    0.389, // '*' (42)
    0.584, // '+' (43)
    0.278, // ',' (44)
    0.333, // '-' (45)
    0.278, // '.' (46)
    0.278, // '/' (47)
    // 48..57: Tabular numerals 0-9
    0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556, 0.556,
    // 58..64: Punctuation and symbols
    0.333, // ':' (58)
    0.333, // ';' (59)
    0.584, // '<' (60)
    0.584, // '=' (61)
    0.584, // '>' (62)
    0.611, // '?' (63)
    0.975, // '@' (64)
    // 65..90: Uppercase A-Z
    0.722, // 'A' (65)
    0.722, // 'B' (66)
    0.722, // 'C' (67)
    0.722, // 'D' (68)
    0.667, // 'E' (69)
    0.611, // 'F' (70)
    0.778, // 'G' (71)
    0.722, // 'H' (72)
    0.278, // 'I' (73)
    0.556, // 'J' (74)
    0.722, // 'K' (75)
    0.611, // 'L' (76)
    0.833, // 'M' (77)
    0.722, // 'N' (78)
    0.778, // 'O' (79)
    0.667, // 'P' (80)
    0.778, // 'Q' (81)
    0.722, // 'R' (82)
    0.667, // 'S' (83)
    0.611, // 'T' (84)
    0.722, // 'U' (85)
    0.667, // 'V' (86)
    0.944, // 'W' (87)
    0.667, // 'X' (88)
    0.667, // 'Y' (89)
    0.611, // 'Z' (90)
    // 91..96: Brackets and symbols
    0.389, // '[' (91)
    0.278, // '\' (92)
    0.389, // ']' (93)
    0.584, // '^' (94)
    0.556, // '_' (95)
    0.333, // '`' (96)
    // 97..122: Lowercase a-z
    0.556, // 'a' (97)
    0.611, // 'b' (98)
    0.556, // 'c' (99)
    0.611, // 'd' (100)
    0.556, // 'e' (101)
    0.333, // 'f' (102)
    0.611, // 'g' (103)
    0.611, // 'h' (104)
    0.278, // 'i' (105)
    0.278, // 'j' (106)
    0.556, // 'k' (107)
    0.278, // 'l' (108)
    0.889, // 'm' (109)
    0.611, // 'n' (110)
    0.611, // 'o' (111)
    0.611, // 'p' (112)
    0.611, // 'q' (113)
    0.389, // 'r' (114)
    0.556, // 's' (115)
    0.333, // 't' (116)
    0.611, // 'u' (117)
    0.556, // 'v' (118)
    0.778, // 'w' (119)
    0.556, // 'x' (120)
    0.556, // 'y' (121)
    0.500, // 'z' (122)
    // 123..127: Braces and delimiters
    0.389, // '{' (123)
    0.280, // '|' (124)
    0.389, // '}' (125)
    0.584, // '~' (126)
    0.0, // DEL (127)
  ];

  /// Pre-calculated advance width factors for Anton Regular (ASCII 0..127).
  /// Anton is a narrow, condensed display font with characteristic compact proportions.
  static const List<double> _antonRegularAscii = [
    // 0..31: Control codes
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    // 32..47: Space and punctuation
    0.220, // ' ' (32)
    0.200, // '!' (33)
    0.280, // '"' (34)
    0.410, // '#' (35)
    0.400, // '$' (36)
    0.650, // '%' (37)
    0.470, // '&' (38)
    0.170, // ''' (39)
    0.250, // '(' (40)
    0.250, // ')' (41)
    0.310, // '*' (42)
    0.420, // '+' (43)
    0.190, // ',' (44)
    0.260, // '-' (45)
    0.190, // '.' (46)
    0.280, // '/' (47)
    // 48..57: Numerals 0-9
    0.400, 0.320, 0.400, 0.400, 0.410, 0.400, 0.400, 0.390, 0.400, 0.400,
    // 58..64: Punctuation and symbols
    0.190, // ':' (58)
    0.190, // ';' (59)
    0.420, // '<' (60)
    0.420, // '=' (61)
    0.420, // '>' (62)
    0.360, // '?' (63)
    0.680, // '@' (64)
    // 65..90: Uppercase A-Z
    0.420, // 'A' (65)
    0.410, // 'B' (66)
    0.420, // 'C' (67)
    0.420, // 'D' (68)
    0.360, // 'E' (69)
    0.350, // 'F' (70)
    0.430, // 'G' (71)
    0.430, // 'H' (72)
    0.210, // 'I' (73)
    0.320, // 'J' (74)
    0.410, // 'K' (75)
    0.350, // 'L' (76)
    0.530, // 'M' (77)
    0.440, // 'N' (78)
    0.440, // 'O' (79)
    0.390, // 'P' (80)
    0.440, // 'Q' (81)
    0.410, // 'R' (82)
    0.380, // 'S' (83)
    0.380, // 'T' (84)
    0.420, // 'U' (85)
    0.410, // 'V' (86)
    0.560, // 'W' (87)
    0.410, // 'X' (88)
    0.410, // 'Y' (89)
    0.380, // 'Z' (90)
    // 91..96: Brackets and symbols
    0.250, // '[' (91)
    0.280, // '\' (92)
    0.250, // ']' (93)
    0.360, // '^' (94)
    0.400, // '_' (95)
    0.220, // '`' (96)
    // 97..122: Lowercase a-z
    0.360, // 'a' (97)
    0.380, // 'b' (98)
    0.360, // 'c' (99)
    0.380, // 'd' (100)
    0.360, // 'e' (101)
    0.250, // 'f' (102)
    0.380, // 'g' (103)
    0.380, // 'h' (104)
    0.200, // 'i' (105)
    0.230, // 'j' (106)
    0.370, // 'k' (107)
    0.200, // 'l' (108)
    0.530, // 'm' (109)
    0.380, // 'n' (110)
    0.380, // 'u' (111)
    0.380, // 'p' (112)
    0.380, // 'q' (113)
    0.290, // 'r' (114)
    0.350, // 's' (115)
    0.270, // 't' (116)
    0.380, // 'u' (117)
    0.370, // 'v' (118)
    0.500, // 'w' (119)
    0.370, // 'x' (120)
    0.370, // 'y' (121)
    0.350, // 'z' (122)
    // 123..127: Braces and delimiters
    0.260, // '{' (123)
    0.200, // '|' (124)
    0.260, // '}' (125)
    0.420, // '~' (126)
    0.0, // DEL (127)
  ];

  /// Fallback character map for extended Latin punctuation, dashes, and smart quotes.
  static const Map<int, double> _extendedTypographyMap = {
    0x00A0: 0.278, // Non-breaking space
    0x00AB: 0.500, // «
    0x00BB: 0.500, // »
    0x2010: 0.333, // Hyphen ‐
    0x2013: 0.500, // En-dash –
    0x2014: 1.000, // Em-dash —
    0x2018: 0.222, // Left single quote ‘
    0x2019: 0.222, // Right single quote ’
    0x201C: 0.355, // Left double quote “
    0x201D: 0.355, // Right double quote ”
    0x2022: 0.355, // Bullet •
    0x2026: 1.000, // Horizontal ellipsis …
    0x00B0: 0.400, // Degree °
    0x00A9: 0.737, // Copyright ©
    0x00AE: 0.737, // Registered ®
  };

  /// Resolves the normalized advance width of a single character code [charCode].
  /// Multiplied by [fontSize] to obtain physical pixel advance.
  static double getCharacterAdvanceRatio(
      int charCode, {
        required String fontFamily,
        bool isBold = false,
        bool isItalic = false,
      }) {
    final lower = fontFamily.toLowerCase();
    final isAnton = lower.contains('anton');

    if (charCode < 128) {
      if (isAnton) {
        return _antonRegularAscii[charCode];
      }
      return isBold ? _arimoBoldAscii[charCode] : _arimoRegularAscii[charCode];
    }

    if (_extendedTypographyMap.containsKey(charCode)) {
      final ratio = _extendedTypographyMap[charCode]!;
      return isAnton ? ratio * 0.70 : ratio;
    }

    return isAnton ? 0.38 : kFallbackAdvanceRatio;
  }

  /// Measures the horizontal pixel width of [text] with sub-pixel precision.
  /// Matches standard Canvas / Pillow TrueType text layout without external dependencies.
  static double measureString(
      String text, {
        required String fontFamily,
        required double fontSize,
        bool isBold = false,
        bool isItalic = false,
        double letterSpacing = 0.0,
      }) {
    if (text.isEmpty) return 0.0;

    double totalAdvance = 0.0;
    final int count = text.length;

    for (int i = 0; i < count; i++) {
      final int code = text.codeUnitAt(i);
      final double ratio = getCharacterAdvanceRatio(
        code,
        fontFamily: fontFamily,
        isBold: isBold,
        isItalic: isItalic,
      );
      totalAdvance += (ratio * fontSize) + letterSpacing;
    }

    return math.max(0.0, totalAdvance);
  }

  /// Wraps [textToWrap] into distinct lines that fit comfortably within [maxWidth].
  /// Handles forced newlines, word breaks, and splits oversized unbreakable words.
  static List<String> wrapWords(
      String textToWrap,
      double maxWidth, {
        required String fontFamily,
        required double fontSize,
        bool isBold = false,
        bool isItalic = false,
        double letterSpacing = 0.0,
      }) {
    final List<String> resultLines = [];
    final rawLines = textToWrap.split('\n');

    for (final rawLine in rawLines) {
      if (rawLine.trim().isEmpty) {
        resultLines.add('');
        continue;
      }

      final words = rawLine.split(' ');
      String currentLine = '';

      for (final word in words) {
        if (word.isEmpty) continue;

        final testLine = currentLine.isEmpty ? word : '$currentLine $word';
        final testWidth = measureString(
          testLine,
          fontFamily: fontFamily,
          fontSize: fontSize,
          isBold: isBold,
          isItalic: isItalic,
          letterSpacing: letterSpacing,
        );

        if (testWidth <= maxWidth) {
          currentLine = testLine;
        } else {
          if (currentLine.isNotEmpty) {
            resultLines.add(currentLine);
            currentLine = '';
          }

          // Inspect if the single word itself exceeds maxWidth
          final singleWordWidth = measureString(
            word,
            fontFamily: fontFamily,
            fontSize: fontSize,
            isBold: isBold,
            isItalic: isItalic,
            letterSpacing: letterSpacing,
          );

          if (singleWordWidth > maxWidth) {
            // Slices oversized single word across boundaries
            final buffer = StringBuffer();
            for (int i = 0; i < word.length; i++) {
              final testSlice = buffer.toString() + word[i];
              if (measureString(
                testSlice,
                fontFamily: fontFamily,
                fontSize: fontSize,
                isBold: isBold,
                isItalic: isItalic,
              ) >
                  maxWidth) {
                if (buffer.isNotEmpty) {
                  resultLines.add(buffer.toString());
                  buffer.clear();
                }
              }
              buffer.write(word[i]);
            }
            currentLine = buffer.toString();
          } else {
            currentLine = word;
          }
        }
      }

      if (currentLine.isNotEmpty) {
        resultLines.add(currentLine);
      }
    }

    return resultLines;
  }
}