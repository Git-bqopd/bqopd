import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../services/username_service.dart';

class FirebaseUserRepository implements IUserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Stream<UserProfile?> watchUser(String uid) {
    return _db.collection('profiles').doc(uid).snapshots().map((doc) => doc.exists ? UserProfile.fromMap(doc.id, doc.data() as Map<String, dynamic>) : null);
  }

  @override
  Stream<UserAccount?> watchUserAccount(String uid) {
    return _db.collection('Users').doc(uid).snapshots().map((doc) => doc.exists ? UserAccount.fromMap(doc.id, doc.data() as Map<String, dynamic>) : null);
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

    final batch = _db.batch();
    if (publicData.isNotEmpty) batch.set(_db.collection('profiles').doc(uid), publicData, SetOptions(merge: true));
    if (privateData.isNotEmpty) batch.set(_db.collection('Users').doc(uid), privateData, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Stream<List<Map<String, dynamic>>> watchUserWorks(String uid) {
    return _db.collection('fanzines').where('editorId', isEqualTo: uid).snapshots().map((s) => s.docs.map((d) => d.data()).toList());
  }

  @override
  Stream<List<Map<String, dynamic>>> watchUserMentions(String uid) {
    return _db.collection('fanzines').where('mentionedUsers', arrayContains: 'user:$uid').snapshots().map((s) => s.docs.map((d) => d.data()).toList());
  }

  @override
  Future<String?> claimHandleForUser(String handle) async {
    return await claimHandle(handle);
  }
}