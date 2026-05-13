import 'package:cloud_firestore/cloud_firestore.dart';

/// Extracted from pure dart core package as it relies on Firebase
class MentionParser {
  static final RegExp _wikiLinkRegex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');

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

      String handleCandidate = code.toLowerCase();
      var userDoc = await db.collection('usernames').doc(handleCandidate).get();

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
          final targetDoc = await db.collection('usernames').doc(targetHandle).get();
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
}