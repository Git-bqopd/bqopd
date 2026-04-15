import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProvider with ChangeNotifier {
  User? _user;
  Map<String, dynamic>? _userProfile;
  Map<String, bool> _socialButtonVisibility = {};
  bool _isLoading = true;

  UserProvider() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _user = user;
      if (user != null) {
        _fetchUserProfile(user.uid);
      } else {
        _userProfile = null;
        _socialButtonVisibility = {};
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  // --- CORE GETTERS ---
  User? get user => _user;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, bool> get socialButtonVisibility => _socialButtonVisibility;

  bool get isLoggedIn => _user != null;
  String? get currentUserId => _user?.uid;
  bool get isLoading => _isLoading;

  bool get isEditor {
    if (_userProfile == null) return false;
    final role = _userProfile!['role'];
    final isEd = _userProfile!['isEditor'];
    final capEditor = _userProfile!['Editor']; // FIXED: Catch the capital 'E' field

    return role == 'editor' ||
        role == 'admin' ||
        role == 'curator' ||
        role == 'moderator' ||
        isEd == true ||
        capEditor == true;
  }

  Future<void> _fetchUserProfile(String uid) async {
    _isLoading = true;
    notifyListeners();

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (doc.exists) {
        _userProfile = doc.data() as Map<String, dynamic>;

        // Fetch saved preferences if they exist
        if (_userProfile!.containsKey('preferences') && _userProfile!['preferences'] is Map) {
          final prefs = _userProfile!['preferences'] as Map<String, dynamic>;
          if (prefs.containsKey('socialButtons') && prefs['socialButtons'] is Map) {
            _socialButtonVisibility = Map<String, bool>.from(prefs['socialButtons']);
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- METHODS FOR SETTINGS PANEL ---

  void toggleSocialButtonVisibility(String toolId) {
    toggleSocialButton(toolId);
  }

  void toggleSocialButton(String toolId) {
    // Default is true if not explicitly set
    final currentVal = _socialButtonVisibility[toolId] ?? true;
    _socialButtonVisibility[toolId] = !currentVal;

    // Notify listeners so the UI updates immediately
    notifyListeners();

    // Save to Firestore asynchronously
    _savePreferences();
  }

  Future<void> _savePreferences() async {
    if (_user == null) return;

    try {
      await FirebaseFirestore.instance.collection('Users').doc(_user!.uid).set({
        'preferences': {
          'socialButtons': _socialButtonVisibility,
        }
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving user preferences: $e");
    }
  }
}