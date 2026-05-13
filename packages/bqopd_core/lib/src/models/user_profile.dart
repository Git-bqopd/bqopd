DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try { return value.toDate(); } catch (_) {}
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Represents the public identity of any entity (Human or Managed).
class UserProfile {
  final String uid;
  final String username;
  final String displayName;
  final String photoUrl;
  final String bio;
  final bool isManaged;
  final bool isCurator;
  final bool isAdmin;
  final List<String> managers;
  final int followerCount;
  final int followingCount;

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
    this.isCurator = false,
    this.isAdmin = false,
    this.managers = const [],
    this.followerCount = 0,
    this.followingCount = 0,
    this.xHandle,
    this.instagramHandle,
    this.githubHandle,
    this.updatedAt,
  });

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    return UserProfile(
      uid: id,
      username: data['username'] ?? '',
      displayName: data['displayName'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      bio: data['bio'] ?? '',
      isManaged: data['isManaged'] ?? false,
      isCurator: data['isCurator'] ?? false,
      isAdmin: data['isAdmin'] ?? false,
      managers: List<String>.from(data['managers'] ?? []),
      followerCount: data['followerCount'] ?? 0,
      followingCount: data['followingCount'] ?? 0,
      xHandle: data['xHandle'],
      instagramHandle: data['instagramHandle'],
      githubHandle: data['githubHandle'],
      updatedAt: _parseDate(data['updatedAt']),
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
      'isCurator': isCurator,
      'isAdmin': isAdmin,
      'managers': managers,
      'followerCount': followerCount,
      'followingCount': followingCount,
      'xHandle': xHandle,
      'instagramHandle': instagramHandle,
      'githubHandle': githubHandle,
      'updatedAt': DateTime.now(),
    };
  }
}