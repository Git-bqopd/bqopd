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

  // --- Session Preferences (Social Toolbar) ---
  // Default: All buttons visible except Terminal and Editor tools
  final Map<String, bool> _socialButtonVisibility = {
    'Comment': true,
    'Share': true,
    'Views': true,
    'Text': true,
    'Circulation': true,
    'Terminal': false, // Starts hidden
    'Approve': false,  // Editor tool - starts hidden
    'Fanzine': false,  // Editor tool - starts hidden
  };

  UserProvider() {
    _init();
  }

  // Getters
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  User? get currentUser => _currentUser;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, bool> get socialButtonVisibility => _socialButtonVisibility;

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

        // --- Sync Toolbar Preferences from Firestore ---
        if (_userProfile != null && _userProfile!.containsKey('socialToolbar')) {
          final savedPrefs = _userProfile!['socialToolbar'];
          if (savedPrefs is Map<String, dynamic>) {
            savedPrefs.forEach((key, value) {
              if (value is bool && _socialButtonVisibility.containsKey(key)) {
                _socialButtonVisibility[key] = value;
              }
            });
          }
        }
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

  // --- Preference Methods ---
  void toggleSocialButton(String key) {
    if (_socialButtonVisibility.containsKey(key)) {
      // 1. Optimistic Update (Instant UI feedback)
      _socialButtonVisibility[key] = !(_socialButtonVisibility[key] ?? true);
      notifyListeners(); // Notify all listeners (SocialToolbars) to rebuild

      // 2. Persist to Firestore if logged in
      if (_currentUser != null) {
        _db.collection('Users').doc(_currentUser!.uid).set({
          'socialToolbar': _socialButtonVisibility
        }, SetOptions(merge: true)).catchError((e) {
          print("Error saving toolbar prefs: $e");
        });
      }
    }
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }
}