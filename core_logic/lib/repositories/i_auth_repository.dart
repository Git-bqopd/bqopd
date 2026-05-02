abstract class IAuthRepository {
  Stream<String?> get authStateChanges;
  String? get currentUserUid;

  Future<void> login(String email, String password);
  Future<void> register({required String email, required String password, required String username});
  Future<void> logout();
}