import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/firebase_mocks.dart';

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
      controller.add(decoded.map((d) => d['data'] as Map<String, dynamic>).toList());
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchUserMentions(String uid) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    final unsub = fsListenQuery('fanzines', 'mentionedUsers', 'array-contains', jsonEncode('user:$uid'), '', false, (String jsonStr) {
      final List decoded = jsonDecode(jsonStr);
      controller.add(decoded.map((d) => d['data'] as Map<String, dynamic>).toList());
    });
    controller.onCancel = () { unsub.callAsFunction(); };
    return controller.stream;
  }

  @override
  Future<String?> claimHandleForUser(String handle) async {
    // Calling the function implemented in the core directly since it handles transactions normally,
    // but pure web transactional implementation requires cloud functions fallback.
    // Given the constraints, returning generic fallback status for pure web.
    return "Web handle claiming requires Flutter context or Functions backend.";
  }
}