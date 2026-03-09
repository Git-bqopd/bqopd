import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class UserProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? _currentUser;
  Map<String, dynamic>? _userProfile;
  StreamSubscription? _profileSubscription;
  bool _isLoading = true;

  // --- Session Preferences (Social Toolbar) ---
  final Map<String, bool> _socialButtonVisibility = {
    'Comment': true,
    'Share': true,
    'Views': true,
    'Text': true,
    'Circulation': true,
    'YouTube': true,
    'Terminal': false,
    'Approve': false,
    'Fanzine': false,
    'Credits': false,
    'Edit': true,
    'OCR': false,      // NEW: Editor tool
    'Entities': false, // NEW: Editor tool
  };

  UserProvider() {
    _init();
  }

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  User? get currentUser => _currentUser;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, bool> get socialButtonVisibility => _socialButtonVisibility;

  String get username => _userProfile?['username'] ?? '';
  bool get isEditor => _userProfile?['Editor'] == true;
  String? get currentUserId => _currentUser?.uid;

  void _init() {
    _auth.authStateChanges().listen((User? user) {
      _currentUser = user;
      if (user != null) {
        _subscribeToUserProfile(user.uid);
      } else {
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
    _profileSubscription = _db.collection('Users').doc(uid).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        _userProfile = snapshot.data();
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
        _userProfile = {};
      }
      _isLoading = false;
      notifyListeners();
    }, onError: (error) {
      debugPrint("UserProvider Error: $error");
      _isLoading = false;
      notifyListeners();
    });
  }

  void toggleSocialButton(String key) {
    if (_socialButtonVisibility.containsKey(key)) {
      _socialButtonVisibility[key] = !(_socialButtonVisibility[key] ?? true);
      notifyListeners();
      if (_currentUser != null) {
        _db.collection('Users').doc(_currentUser!.uid).set(
            {'socialToolbar': _socialButtonVisibility},
            SetOptions(merge: true)).catchError((e) {
          debugPrint("Error saving toolbar prefs: $e");
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