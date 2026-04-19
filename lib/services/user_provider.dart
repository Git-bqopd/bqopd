import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fanzine.dart';

/// Manages the authenticated user's state and their unified profile data.
class UserProvider with ChangeNotifier {
  User? _user;
  Map<String, dynamic>? _userAccount; // From 'Users' collection (private/roles)
  Map<String, dynamic>? _userProfile; // From 'profiles' collection (public)
  Map<String, bool> _socialButtonVisibility = {};
  bool _isLoading = true;

  UserProvider() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _user = user;
      if (user != null) {
        _fetchUserData(user.uid);
      } else {
        _userAccount = null;
        _userProfile = null;
        _socialButtonVisibility = {};
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  User? get user => _user;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, bool> get socialButtonVisibility => _socialButtonVisibility;
  bool get isLoggedIn => _user != null;
  String? get currentUserId => _user?.uid;
  bool get isLoading => _isLoading;

  /// Role check via the private 'Users' collection data.
  bool get isModerator {
    if (_userAccount == null) return false;
    final role = _userAccount!['role'];
    return role == 'admin' || role == 'moderator';
  }

  bool get isCurator {
    if (_userAccount == null) return false;
    if (isModerator) return true;
    final role = _userAccount!['role'];
    return role == 'curator' || _userAccount!['isCurator'] == true;
  }

  bool canEditFanzine(Fanzine fanzine) {
    if (!isLoggedIn) return false;
    if (isModerator) return true;
    if (fanzine.ownerId == _user!.uid) return true;
    if (fanzine.editors.contains(_user!.uid)) return true;
    return false;
  }

  Future<void> _fetchUserData(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      final db = FirebaseFirestore.instance;

      // Fetch Private Account Data
      DocumentSnapshot accountDoc = await db.collection('Users').doc(uid).get();
      if (accountDoc.exists) {
        _userAccount = accountDoc.data() as Map<String, dynamic>;
      }

      // Fetch Public Profile Data
      DocumentSnapshot profileDoc = await db.collection('profiles').doc(uid).get();
      if (profileDoc.exists) {
        _userProfile = profileDoc.data() as Map<String, dynamic>;

        // Load preferences if they exist (staying in profiles for now as it's UI config)
        if (_userProfile!.containsKey('preferences')) {
          final prefs = _userProfile!['preferences'] as Map<String, dynamic>;
          if (prefs.containsKey('socialButtons')) {
            _socialButtonVisibility = Map<String, bool>.from(prefs['socialButtons']);
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void toggleSocialButtonVisibility(String toolId) {
    final currentVal = _socialButtonVisibility[toolId] ?? true;
    _socialButtonVisibility[toolId] = !currentVal;
    notifyListeners();
    _savePreferences();
  }

  Future<void> _savePreferences() async {
    if (_user == null) return;
    try {
      // Preferences are saved to the public profile for easier UI access
      await FirebaseFirestore.instance.collection('profiles').doc(_user!.uid).set({
        'preferences': { 'socialButtons': _socialButtonVisibility }
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}