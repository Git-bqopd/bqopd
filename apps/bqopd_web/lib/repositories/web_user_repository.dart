import 'dart:async';
import 'dart:convert';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/firebase_mocks.dart';

/// Concrete web implementation of IUserRepository.
/// Handles user metadata lookup and real-time public works/mentions synchronizations.
class WebUserRepository implements IUserRepository {
  @override
  Stream<UserProfile?> watchUser(String uid) {
    final controller = StreamController<UserProfile?>();
    final unsub = fsListenDoc('profiles/$uid', (String jsonStr) {
      final decoded = jsonDecode(jsonStr);
      if (decoded['exists'] == true) {
        controller.add(UserProfile.fromMap(decoded['id'], restoreTimestamps(decoded['data'])));
      } else {
        controller.add(null);
      }
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Stream<UserAccount?> watchUserAccount(String uid) {
    final controller = StreamController<UserAccount?>();
    final unsub = fsListenDoc('Users/$uid', (String jsonStr) {
      final decoded = jsonDecode(jsonStr);
      if (decoded['exists'] == true) {
        controller.add(UserAccount.fromMap(decoded['id'], restoreTimestamps(decoded['data'])));
      } else {
        controller.add(null);
      }
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    final publicFields = ['username', 'displayName', 'bio', 'photoUrl', 'xHandle', 'instagramHandle', 'githubHandle', 'updatedAt'];
    final Map<String, dynamic> publicData = {};
    final Map<String, dynamic> privateData = {};
    data.forEach((key, value) {
      if (publicFields.contains(key)) publicData[key] = value;
      else privateData[key] = value;
    });
    if (publicData.isNotEmpty) await fsSetDoc('profiles/$uid', jsonEncode(publicData), true);
    if (privateData.isNotEmpty) await fsSetDoc('Users/$uid', jsonEncode(privateData), true);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchUserWorks(String uid) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    final unsub = fsListenQuery('fanzines', 'editorId', '==', jsonEncode(uid), '', false, (String jsonStr) {
      final List decoded = jsonDecode(jsonStr);
      controller.add(decoded.map((d) {
        final data = restoreTimestamps(d['data'] as Map<String, dynamic>);
        data['id'] = d['id'];
        return data;
      }).toList());
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchUserMentions(String uid) {
    final controller = StreamController<List<Map<String, dynamic>>>();

    // 1. Fetch the target profile's display and username properties for flexible lookup
    fsGetDoc('profiles/$uid').then((profileJson) {
      String displayName = '';
      String username = '';
      try {
        final decoded = jsonDecode(profileJson);
        if (decoded['exists'] == true) {
          final pData = decoded['data'] as Map<String, dynamic>? ?? {};
          displayName = (pData['displayName'] ?? '').toString().trim();
          username = (pData['username'] ?? '').toString().trim();
        }
      } catch (e) {
        print('[watchUserMentions Error fetching profile] $e');
      }

      // 2. Perform a clean, unindexed query to retrieve all fanzines and resolve mentions in-memory
      final unsub = fsListenQuery('fanzines', '', '', '', '', false, (String jsonStr) {
        try {
          final List decoded = jsonDecode(jsonStr);
          final List<Map<String, dynamic>> filtered = [];

          for (var item in decoded) {
            final Map<String, dynamic> data = restoreTimestamps(item['data'] as Map<String, dynamic>?);
            data['id'] = item['id'];

            // GUARD: Only public/live fanzines are allowed to show up on the public profile page
            if (data['isLive'] != true) continue;

            bool isMentioned = false;

            // Step A: Check explicit mentionedUsers registry array (e.g. "user:UID")
            final List mentionedUsers = data['mentionedUsers'] ?? [];
            if (mentionedUsers.contains('user:$uid')) {
              isMentioned = true;
            }

            // Step B: Check raw draftEntities list for name/username/alias matching (case-insensitive)
            if (!isMentioned) {
              final List draftEntities = data['draftEntities'] ?? [];
              final lowerEntities = draftEntities.map((e) => e.toString().toLowerCase().trim()).toList();

              if (displayName.isNotEmpty && lowerEntities.contains(displayName.toLowerCase())) {
                isMentioned = true;
              }
              if (!isMentioned && username.isNotEmpty && lowerEntities.contains(username.toLowerCase())) {
                isMentioned = true;
              }
            }

            if (isMentioned) {
              filtered.add(data);
            }
          }

          // Sort in descending order of publishing or creation timestamps
          filtered.sort((a, b) {
            final aT = a['publishedAt'] ?? a['creationDate'] ?? a['createdAt'] ?? 0;
            final bT = b['publishedAt'] ?? b['creationDate'] ?? b['createdAt'] ?? 0;
            return bT.toString().compareTo(aT.toString());
          });

          if (!controller.isClosed) {
            controller.add(filtered);
          }
        } catch (e) {
          print('[watchUserMentions parse error] $e');
        }
      });

      controller.onCancel = () {
        unsub.callAsFunction();
      };
    }).catchError((err) {
      print('[watchUserMentions global error] $err');
      if (!controller.isClosed) {
        controller.add([]);
      }
    });

    return controller.stream;
  }

  @override
  Future<String?> claimHandleForUser(String handle) async {
    return "Web handle claiming requires Flutter context or Functions backend.";
  }
}