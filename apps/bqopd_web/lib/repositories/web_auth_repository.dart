@JS()
library web_auth_repository;

import 'dart:async';
import 'dart:js_interop';

import 'package:bqopd_core/src/interfaces/auth_repository_interface.dart';
import 'package:bqopd_core/src/models/auth_user.dart';

@JS('loginWithFirebase')
external JSPromise _loginWithFirebase(JSString email, JSString password);

@JS('registerWithFirebase')
external JSPromise _registerWithFirebase(JSString email, JSString password, JSString username);

@JS('logoutFromFirebase')
external JSPromise _logoutFromFirebase();

@JS('getCurrentUserId')
external JSString? _getCurrentUserId();

@JS('getCurrentUserEmail')
external JSString? _getCurrentUserEmail();

@JS('onAuthStateChangedListener')
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
  Stream<AuthUser?> get authStateChanges {
    final controller = StreamController<AuthUser?>.broadcast();

    // Emit the active authentication status immediately to new subscribers on a fresh tick
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(currentUser);
      }
    });

    // Pipe future updates from our central auth status channel
    final subscription = _authController.stream.listen(
          (user) {
        if (!controller.isClosed) {
          controller.add(user);
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );

    controller.onCancel = () {
      subscription.cancel();
    };

    return controller.stream;
  }

  @override
  Future<void> login(String email, String password) async {
    await _loginWithFirebase(email.toJS, password.toJS).toDart;
  }

  @override
  Future<void> register({required String email, required String password, required String username}) async {
    await _registerWithFirebase(email.toJS, password.toJS, username.toJS).toDart;
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