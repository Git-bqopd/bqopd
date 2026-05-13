import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../services/user_bootstrap.dart';

class FirebaseAuthRepository implements IAuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Stream<AuthUser?> get authStateChanges => _auth.authStateChanges().map((u) {
    return u != null ? AuthUser(uid: u.uid, email: u.email) : null;
  });

  @override
  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    await ensureUserDocument();
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String username,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
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
      await _db.collection('usernames').doc(username.toLowerCase()).set({
        'uid': cred.user!.uid,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Future<void> logout() async => await _auth.signOut();

  @override
  AuthUser? get currentUser {
    final u = _auth.currentUser;
    return u != null ? AuthUser(uid: u.uid, email: u.email) : null;
  }
}