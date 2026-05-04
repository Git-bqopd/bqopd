import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the private system data of an authenticated human user.
class UserAccount {
  final String uid;
  final String email;
  final String role; // admin, moderator, curator, user (Legacy field)
  final List<String> roles; // Multi-select roles: admin, moderator, curator
  final bool isCurator;

  // Real Name / Contact
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

  factory UserAccount.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserAccount(
      uid: doc.id,
      email: data['email'] ?? '',
      role: data['role'] ?? 'user',
      roles: List<String>.from(data['roles'] ?? []),
      isCurator: data['isCurator'] ?? false,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      street1: data['street1'],
      street2: data['street2'],
      city: data['city'],
      state: data['state'],
      zipCode: data['zipCode'],
      country: data['country'],
      preferences: Map<String, dynamic>.from(data['preferences'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
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
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}