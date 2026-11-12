DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try { return value.toDate(); } catch (_) {}
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Represents the private system data of an authenticated human user.
class UserAccount {
  final String uid;
  final String email;
  final String role;
  final List<String> roles;
  final bool isCurator;

  // Discrete capability switches sourced from Auth Custom Claims
  final bool isAdmin;
  final bool isModerator;
  final bool isCuratorRole;
  final bool isTerminalGM;

  final String firstName;
  final String lastName;
  final String? street1;
  final String? street2;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;

  final Map<String, dynamic> preferences;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserAccount({
    required this.uid,
    required this.email,
    this.role = 'user',
    this.roles = const [],
    this.isCurator = false,
    this.isAdmin = false,
    this.isModerator = false,
    this.isCuratorRole = false,
    this.isTerminalGM = false,
    this.firstName = '',
    this.lastName = '',
    this.street1,
    this.street2,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.preferences = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory UserAccount.fromMap(String id, Map<String, dynamic> data) {
    final rawRoles = List<String>.from(data['roles'] ?? []);
    final r = (data['role'] ?? 'user').toString();

    // Check both explicit boolean flags, the legacy role string, and roles list
    final bool adminClaim = data['isAdmin'] == true ||
        data['admin'] == true ||
        r == 'admin' ||
        rawRoles.contains('admin');

    final bool modClaim = data['isModerator'] == true ||
        data['moderator'] == true ||
        r == 'moderator' ||
        rawRoles.contains('moderator');

    final bool curatorClaim = data['isCuratorRole'] == true ||
        data['isCurator'] == true ||
        data['curator'] == true ||
        r == 'curator' ||
        rawRoles.contains('curator');

    final bool gmClaim = data['isTerminalGM'] == true ||
        data['terminalGM'] == true ||
        rawRoles.contains('terminalGM');

    return UserAccount(
      uid: id,
      email: data['email'] ?? '',
      role: r,
      roles: rawRoles,
      isCurator: curatorClaim,
      isAdmin: adminClaim,
      isModerator: modClaim,
      isCuratorRole: curatorClaim,
      isTerminalGM: gmClaim,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      street1: data['street1'],
      street2: data['street2'],
      city: data['city'],
      state: data['state'],
      zipCode: data['zipCode'],
      country: data['country'],
      preferences: Map<String, dynamic>.from(data['preferences'] ?? {}),
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'role': role,
      'roles': roles,
      'isCurator': isCurator,
      'firstName': firstName,
      'lastName': lastName,
      'street1': street1,
      'street2': street2,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'country': country,
      'preferences': preferences,
      'updatedAt': DateTime.now(),
    };
  }
}