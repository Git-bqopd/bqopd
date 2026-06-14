import 'package:cloud_firestore/cloud_firestore.dart';

/// Service responsible for parsing wiki-links and resolving user mentions.
/// Moved from utils to be a proper service in the Flutter app layer.
class MentionService {
  static final RegExp _wikiLinkRegex = RegExp(r'\[\[(.*?)\]\]');
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<String>> parseMentions(String text) async {
    final Set<String> mentions = {};
    final matches = _wikiLinkRegex.allMatches(text);
    for (final match in matches) {
      final content = match.group(1) ?? '';
      final parts = content.split('|');
      if (parts.isEmpty) continue;

      String display = parts[0].trim();
      String? explicitId;
      if (parts.length == 2 && parts[1].contains(':')) {
        explicitId = parts[1].trim();
      } else if (parts.length >= 3) {
        explicitId = parts[2].trim();
      }

      if (explicitId != null && explicitId.isNotEmpty) {
        mentions.add(explicitId);
        continue;
      }

      String code = display;
      if (code.isEmpty) continue;
      String handleCandidate = code.toLowerCase();
      var userDoc = await _db.collection('usernames').doc(handleCandidate).get();
      if (!userDoc.exists) {
        final hyphenated = handleCandidate.replaceAll(' ', '-');
        if (hyphenated != handleCandidate) {
          userDoc = await _db.collection('usernames').doc(hyphenated).get();
        }
      }
      if (userDoc.exists) {
        final data = userDoc.data()!;
        if (data.containsKey('redirect')) {
          final targetHandle = data['redirect'];
          final targetDoc = await _db.collection('usernames').doc(targetHandle).get();
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