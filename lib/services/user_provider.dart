import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class UserProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? _currentUser;
  Map<String, dynamic>? _userProfile;
  StreamSubscription? _profileSubscription;
  bool _isLoading = true;

  UserProvider() {
    _init();
  }

  // Getters
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  User? get currentUser => _currentUser;
  Map<String, dynamic>? get userProfile => _userProfile;

  // Helpers
  String get username => _userProfile?['username'] ?? '';
  bool get isEditor => _userProfile?['Editor'] == true;
  String? get currentUserId => _currentUser?.uid;

  void _init() {
    // Listen to Auth State (Login/Logout)
    _auth.authStateChanges().listen((User? user) {
      _currentUser = user;

      if (user != null) {
        // User logged in -> Subscribe to Firestore Doc
        _subscribeToUserProfile(user.uid);
      } else {
        // User logged out -> Clear data
        _userProfile = null;
        _isLoading = false;
        _profileSubscription?.cancel();
        notifyListeners();
      }
    });
  }

  void _subscribeToUserProfile(String uid) {
    _isLoading = true;
    notifyListeners();

    _profileSubscription?.cancel();
    _profileSubscription = _db
        .collection('Users')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        _userProfile = snapshot.data();
      } else {
        // Doc doesn't exist yet (or deleted)
        _userProfile = {};
      }
      _isLoading = false;
      notifyListeners();
    }, onError: (error) {
      print("UserProvider Error: $error");
      _isLoading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }
}