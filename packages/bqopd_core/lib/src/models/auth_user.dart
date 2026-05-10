import 'package:equatable/equatable.dart';

/// A pure Dart representation of a User, decoupled from firebase_auth.
class AuthUser extends Equatable {
  final String uid;
  final String? email;

  const AuthUser({
    required this.uid,
    this.email,
  });

  @override
  List<Object?> get props => [uid, email];
}