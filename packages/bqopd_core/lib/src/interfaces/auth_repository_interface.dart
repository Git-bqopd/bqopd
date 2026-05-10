import '../models/auth_user.dart';

/// Abstract interface to safely share Auth logic between Flutter and Jaspr.
abstract class IAuthRepository {
  Stream<AuthUser?> get authStateChanges;

  Future<void> login(String email, String password);

  Future<void> register({
    required String email,
    required String password,
    required String username,
  });

  Future<void> logout();

  AuthUser? get currentUser;
}