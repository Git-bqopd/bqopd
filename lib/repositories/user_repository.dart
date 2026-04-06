import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_bootstrap.dart';
import '../services/username_service.dart';

/// Repository responsible for User profiles, handles, and following relationships.
class UserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Returns a stream of a user's profile data.
  Stream<DocumentSnapshot> watchUser(String uid) {
    return _db.collection('Users').doc(uid).snapshots();
  }

  /// Updates a user profile.
  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    await _db.collection('Users').doc(uid).set(data, SetOptions(merge: true));
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

  /// Creates a managed profile (estate).
  Future<String?> createEstateProfile({
    required String first,
    required String last,
    required String bio,
  }) async {
    return await createManagedProfile(
        firstName: first,
        lastName: last,
        bio: bio
    );
  }
}