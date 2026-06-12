import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../services/username_service.dart';

/// Concrete Firebase implementation of the IUserRepository interface.
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
    final controller = StreamController<List<Map<String, dynamic>>>();

    // 1. Retrieve the target profile metrics to verify display name and handle occurrences
    _db.collection('profiles').doc(uid).get().then((profileSnap) {
      String displayName = '';
      String username = '';
      if (profileSnap.exists && profileSnap.data() != null) {
        final pData = profileSnap.data()!;
        displayName = (pData['displayName'] ?? '').toString().trim();
        username = (pData['username'] ?? '').toString().trim();
      }

      // 2. Perform an unindexed snapshot query and filter in-memory to prevent complex query crashes
      final subscription = _db.collection('fanzines').snapshots().listen((snapshot) {
        final List<Map<String, dynamic>> filtered = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;

          // GUARD: Only public/live fanzines are allowed to show up on the public profile page
          if (data['isLive'] != true) continue;

          bool isMentioned = false;

          // Step A: Check explicit mentionedUsers array
          final List mentionedUsers = data['mentionedUsers'] ?? [];
          if (mentionedUsers.contains('user:$uid')) {
            isMentioned = true;
          }

          // Step B: Check draftEntities list for name/username/alias matching (case-insensitive)
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

        // Sort descending
        filtered.sort((a, b) {
          final aT = a['publishedAt'] ?? a['creationDate'] ?? a['createdAt'] ?? 0;
          final bT = b['publishedAt'] ?? b['creationDate'] ?? b['createdAt'] ?? 0;
          return bT.toString().compareTo(aT.toString());
        });

        if (!controller.isClosed) {
          controller.add(filtered);
        }
      });

      controller.onCancel = () {
        subscription.cancel();
      };
    }).catchError((err) {
      if (!controller.isClosed) {
        controller.add([]);
      }
    });

    return controller.stream;
  }

  @override
  Future<String?> claimHandleForUser(String handle) async {
    return await claimHandle(handle);
  }
}