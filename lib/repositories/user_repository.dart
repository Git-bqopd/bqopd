import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_bootstrap.dart';
import '../services/username_service.dart';

/// Repository responsible for User profiles, handles, and following relationships.
class UserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Returns a stream of a user's PUBLIC profile data.
  Stream<DocumentSnapshot> watchUser(String uid) {
    return _db.collection('profiles').doc(uid).snapshots();
  }

  /// Returns a stream of a user's PRIVATE account data (roles, etc).
  Stream<DocumentSnapshot> watchUserAccount(String uid) {
    return _db.collection('Users').doc(uid).snapshots();
  }

  /// Updates a user profile (Public fields go to 'profiles', private to 'Users').
  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    final publicFields = ['username', 'displayName', 'bio', 'photoUrl', 'updatedAt'];

    final Map<String, dynamic> publicData = {};
    final Map<String, dynamic> privateData = {};

    data.forEach((key, value) {
      if (publicFields.contains(key)) {
        publicData[key] = value;
      } else {
        privateData[key] = value;
      }
    });

    final batch = _db.batch();
    if (publicData.isNotEmpty) {
      batch.set(_db.collection('profiles').doc(uid), publicData, SetOptions(merge: true));
    }
    if (privateData.isNotEmpty) {
      batch.set(_db.collection('Users').doc(uid), privateData, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Fetches fanzines where the user is an editor.
  Stream<QuerySnapshot> watchUserWorks(String uid) {
    return _db
        .collection('fanzines')
        .where('editorId', isEqualTo: uid)
        .orderBy('creationDate', descending: true)
        .snapshots();
  }

  /// Fetches fanzines where the user is mentioned.
  Stream<QuerySnapshot> watchUserMentions(String uid) {
    return _db
        .collection('fanzines')
        .where('mentionedUsers', arrayContains: 'user:$uid')
        .orderBy('creationDate', descending: true)
        .snapshots();
  }

  /// Claims a unique handle for a user.
  Future<String?> claimHandleForUser(String handle) async {
    return await claimHandle(handle);
  }
}