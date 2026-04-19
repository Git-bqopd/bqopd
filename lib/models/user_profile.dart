import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the public identity of any entity (Human or Managed).
class UserProfile {
  final String uid;
  final String username;
  final String displayName;
  final String photoUrl;
  final String bio;
  final bool isManaged;
  final List<String> managers;
  final int followerCount;
  final int followingCount;

  // Social Handles
  final String? xHandle;
  final String? instagramHandle;
  final String? githubHandle;

  final DateTime? updatedAt;

  UserProfile({
    required this.uid,
    required this.username,
    required this.displayName,
    this.photoUrl = '',
    this.bio = '',
    this.isManaged = false,
    this.managers = const [],
    this.followerCount = 0,
    this.followingCount = 0,
    this.xHandle,
    this.instagramHandle,
    this.githubHandle,
    this.updatedAt,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserProfile(
      uid: doc.id,
      username: data['username'] ?? '',
      displayName: data['displayName'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      bio: data['bio'] ?? '',
      isManaged: data['isManaged'] ?? false,
      managers: List<String>.from(data['managers'] ?? []),
      followerCount: data['followerCount'] ?? 0,
      followingCount: data['followingCount'] ?? 0,
      xHandle: data['xHandle'],
      instagramHandle: data['instagramHandle'],
      githubHandle: data['githubHandle'],
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'bio': bio,
      'isManaged': isManaged,
      'managers': managers,
      'followerCount': followerCount,
      'followingCount': followingCount,
      'xHandle': xHandle,
      'instagramHandle': instagramHandle,
      'githubHandle': githubHandle,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}