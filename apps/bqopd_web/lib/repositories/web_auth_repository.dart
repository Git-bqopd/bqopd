import 'dart:async';
import 'dart:js_interop';

import 'package:bqopd_core/src/interfaces/auth_repository_interface.dart';
import 'package:bqopd_core/src/models/auth_user.dart';

@JS('window.loginWithFirebase')
external JSPromise _loginWithFirebase(JSString email, JSString password);

@JS('window.logoutFromFirebase')
external JSPromise _logoutFromFirebase();

@JS('window.getCurrentUserId')
external JSString? _getCurrentUserId();

@JS('window.getCurrentUserEmail')
external JSString? _getCurrentUserEmail();

@JS('window.onAuthStateChangedListener')
external void _onAuthStateChangedListener(JSFunction callback);

/// Pure Dart implementation of IAuthRepository using JS Interop
class WebAuthRepository implements IAuthRepository {
  final StreamController<AuthUser?> _authController = StreamController<AuthUser?>.broadcast();

  WebAuthRepository() {
    _onAuthStateChangedListener(((JSString? uid, JSString? email) {
      if (uid != null) {
        _authController.add(AuthUser(
          uid: uid.toDart,
          email: email?.toDart,
        ));
      } else {
        _authController.add(null);
      }
    }).toJS);
  }

  @override
  Stream<AuthUser?> get authStateChanges => _authController.stream;

  @override
  Future<void> login(String email, String password) async {
    await _loginWithFirebase(email.toJS, password.toJS).toDart;
  }

  @override
  Future<void> register({required String email, required String password, required String username}) async {
    throw UnimplementedError('Registration via Jaspr not fully implemented yet.');
  }

  @override
  Future<void> logout() async {
    await _logoutFromFirebase().toDart;
  }

  @override
  AuthUser? get currentUser {
    final uid = _getCurrentUserId()?.toDart;
    final email = _getCurrentUserEmail()?.toDart;
    if (uid != null) {
      return AuthUser(uid: uid, email: email);
    }
    return null;
  }
}