import 'package:cloud_firestore/cloud_firestore.dart';

class LinkParser {
  // Regex to find [[text]]
  static final RegExp _wikiLinkRegex = RegExp(r'\[\[(.*?)\]\]');

  /// Parses text for [[Shortcode]] and resolves them to database references.
  /// Returns a list of strings like ['user:123', 'fanzine:abc']
  static Future<List<String>> parseMentions(String text) async {
    final Set<String> mentions = {};
    final matches = _wikiLinkRegex.allMatches(text);

    final db = FirebaseFirestore.instance;

    // Iterate through all matches found in the text
    for (final match in matches) {
      String code = match.group(1) ?? '';
      if (code.isEmpty) continue;

      // Normalize the code for DB lookup (typically UPPERCASE for shortcodes)
      String dbKey = code.toUpperCase();

      // 1. Check Master Shortcode Registry
      // We check if this code exists in the 'shortcodes' collection
      final doc = await db.collection('shortcodes').doc(dbKey).get();

      if (doc.exists) {
        final data = doc.data()!;
        final type = data['type'];
        final id = data['contentId'];
        // Add resolved reference (e.g., "fanzine:12345")
        mentions.add('$type:$id');
      } else {
        // 2. Fallback: Check if it's a raw Username
        // Usernames are stored in lowercase in the 'usernames' collection
        final userDoc = await db.collection('usernames').doc(code.toLowerCase()).get();
        if (userDoc.exists) {
          // Add resolved user reference
          mentions.add('user:${userDoc.data()!['uid']}');
        }
      }
    }

    return mentions.toList();
  }
}