import 'dart:math';

/// A pure-Dart utility to generate standard (Base36) and vanity shortcodes.
/// Completely decoupled from Firebase to allow compilations on both Flutter and Jaspr.
class ShortcodeGenerator {
  static const String _base36Chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Generates a standard random 7-character Base36 code.
  static String generateStandardCode() {
    final random = Random();
    String code = '';
    for (int i = 0; i < 7; i++) {
      code += _base36Chars[random.nextInt(_base36Chars.length)];
    }
    return code;
  }

  /// Generates a vanity code with 'bqopd' injected at a random position.
  static String generateVanityCode() {
    final random = Random();
    String randomPart = '';
    for (int i = 0; i < 3; i++) {
      randomPart += _base36Chars[random.nextInt(_base36Chars.length)];
    }

    final insertPos = random.nextInt(4);
    return '${randomPart.substring(0, insertPos)}bqopd${randomPart.substring(insertPos)}';
  }
}