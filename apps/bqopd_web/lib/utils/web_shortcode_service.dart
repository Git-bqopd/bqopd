import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import 'web_firebase_interop.dart';

/// Client-side Web service for shortcode validation and registration.
/// Fully compatible with both server-side SSR stubs and client-side JS interop.
class WebShortcodeService {
  /// Generates a unique shortcode, checks for database collisions,
  /// and registers it in the 'shortcodes' lookup collection.
  static Future<String?> assignShortcode({
    required String contentType,
    required String contentId,
    bool isVanity = false,
  }) async {
    String displayCode;
    String dbKey;

    bool isUnique = false;
    int retries = 0;
    const int maxRetries = 10;

    while (!isUnique && retries < maxRetries) {
      if (isVanity) {
        displayCode = ShortcodeGenerator.generateVanityCode();
      } else {
        displayCode = ShortcodeGenerator.generateStandardCode();
      }

      dbKey = displayCode.toUpperCase();

      // Check collision in 'shortcodes' master registry
      final String scRes = await fsGetDoc('shortcodes/$dbKey');
      final Map<String, dynamic> scDoc = jsonDecode(scRes) as Map<String, dynamic>;

      // Check collision in 'usernames' (stored as lowercase)
      final String unRes = await fsGetDoc('usernames/${dbKey.toLowerCase()}');
      final Map<String, dynamic> unDoc = jsonDecode(unRes) as Map<String, dynamic>;

      if (scDoc['exists'] != true && unDoc['exists'] != true) {
        isUnique = true;
        try {
          // Register in the master shortcodes registry
          final scData = {
            'type': contentType,
            'contentId': contentId,
            'displayCode': displayCode,
            'createdAt': WebFieldValue.serverTimestamp(),
          };

          await fsSetDoc('shortcodes/$dbKey', jsonEncode(scData), true);
          return displayCode;
        } catch (e) {
          print('[WEB SHORTCODE SERVICE ERROR] Failed to write shortcode: $e');
          rethrow;
        }
      }
      retries++;
    }

    if (retries >= maxRetries) {
      throw Exception('Failed to generate a unique shortcode after $maxRetries retries.');
    }
    return null;
  }
}