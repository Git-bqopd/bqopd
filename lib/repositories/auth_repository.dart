import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_bootstrap.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stream of Auth user changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Login with email and password
  Future<UserCredential> login(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    // Ensure the Firestore user document exists upon successful login
    await ensureUserDocument();
    return cred;
  }

  /// Register a new user and initialize their document
  Future<void> register({
    required String email,
    required String password,
    required String username,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (cred.user != null) {
      await _db.collection('Users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': email,
        'username': username,
        'createdAt': FieldValue.serverTimestamp(),
        'Editor': false,
        'bio': '',
        'firstName': '',
        'lastName': '',
      });
      // Handle registry for the new handle
      await _db.collection('usernames').doc(username.toLowerCase()).set({
        'uid': cred.user!.uid,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Sign out
  Future<void> logout() async {
    await _auth.signOut();
  }

  /// Get current user
  User? get currentUser => _auth.currentUser;
}