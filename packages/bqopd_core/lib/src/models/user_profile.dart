DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try { return value.toDate(); } catch (_) {}
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Ordered keys for the seven days of the week used in business schedules.
const List<String> kBusinessDaysOfWeek = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// Human-readable labels corresponding to [kBusinessDaysOfWeek].
const Map<String, String> kBusinessDayLabels = {
  'monday': 'Monday',
  'tuesday': 'Tuesday',
  'wednesday': 'Wednesday',
  'thursday': 'Thursday',
  'friday': 'Friday',
  'saturday': 'Saturday',
  'sunday': 'Sunday',
};

/// Operating hours for a single day of the week on a public business profile.
class BusinessDayHours {
  final bool isOpen;
  final String open;
  final String close;

  const BusinessDayHours({
    this.isOpen = false,
    this.open = '',
    this.close = '',
  });

  BusinessDayHours copyWith({
    bool? isOpen,
    String? open,
    String? close,
  }) {
    return BusinessDayHours(
      isOpen: isOpen ?? this.isOpen,
      open: open ?? this.open,
      close: close ?? this.close,
    );
  }

  factory BusinessDayHours.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const BusinessDayHours();
    final String openVal = (data['open'] ?? '').toString();
    final String closeVal = (data['close'] ?? '').toString();
    final bool inferredOpen =
        openVal.trim().isNotEmpty || closeVal.trim().isNotEmpty;
    return BusinessDayHours(
      isOpen: data['isOpen'] is bool ? data['isOpen'] as bool : inferredOpen,
      open: openVal,
      close: closeVal,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isOpen': isOpen,
      'open': open.trim(),
      'close': close.trim(),
    };
  }
}

/// Returns an initialized 7-day map with all days marked closed.
Map<String, BusinessDayHours> createDefaultBusinessHours() {
  return {
    for (final day in kBusinessDaysOfWeek) day: const BusinessDayHours(),
  };
}

/// Parses raw Firestore map data into a complete 7-day [BusinessDayHours] map.
Map<String, BusinessDayHours> parseBusinessHours(dynamic raw) {
  final result = createDefaultBusinessHours();
  if (raw is Map) {
    for (final day in kBusinessDaysOfWeek) {
      final entry = raw[day];
      if (entry is Map) {
        result[day] =
            BusinessDayHours.fromMap(Map<String, dynamic>.from(entry));
      }
    }
  }
  return result;
}

/// Serializes a [BusinessDayHours] map into a Firestore-compatible map.
Map<String, Map<String, dynamic>> serializeBusinessHours(
    Map<String, BusinessDayHours> hours) {
  return {
    for (final day in kBusinessDaysOfWeek)
      day: (hours[day] ?? const BusinessDayHours()).toMap(),
  };
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

  final String profileType; // 'person' | 'business'
  final bool isOpenToPublic;
  final Map<String, BusinessDayHours> businessHours;

  final String? xHandle;
  final String? instagramHandle;
  final String? githubHandle;

  final DateTime? updatedAt;

  bool get isBusiness => profileType == 'business';

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
    this.profileType = 'person',
    this.isOpenToPublic = false,
    this.businessHours = const {},
    this.xHandle,
    this.instagramHandle,
    this.githubHandle,
    this.updatedAt,
  });

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    final String resolvedType =
        (data['profileType']?.toString() == 'business' ||
                data['isBusiness'] == true)
            ? 'business'
            : 'person';
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
      profileType: resolvedType,
      isOpenToPublic: data['isOpenToPublic'] == true,
      businessHours: parseBusinessHours(data['businessHours']),
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
      'profileType': profileType,
      'isBusiness': isBusiness,
      'isOpenToPublic': isOpenToPublic,
      'businessHours': serializeBusinessHours(businessHours),
      'xHandle': xHandle,
      'instagramHandle': instagramHandle,
      'githubHandle': githubHandle,
      'updatedAt': DateTime.now(),
    };
  }
}