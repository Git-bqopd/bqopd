import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fanzine.dart';
import '../models/user_profile.dart';
import '../models/user_account.dart';

class UserProvider with ChangeNotifier {
  User? _user;
  UserAccount? _userAccount;
  UserProfile? _userProfile;
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
  UserProfile? get userProfile => _userProfile;
  UserAccount? get userAccount => _userAccount;
  Map<String, bool> get socialButtonVisibility => _socialButtonVisibility;
  bool get isLoggedIn => _user != null;
  String? get currentUserId => _user?.uid;
  bool get isLoading => _isLoading;

  bool get isModerator {
    if (_userAccount == null) return false;
    return _userAccount!.role == 'admin' || _userAccount!.role == 'moderator';
  }

  bool get isCurator {
    if (_userAccount == null) return false;
    if (isModerator) return true;
    return _userAccount!.role == 'curator' || _userAccount!.isCurator;
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

      final results = await Future.wait([
        db.collection('Users').doc(uid).get(),
        db.collection('profiles').doc(uid).get(),
      ]);

      if (results[0].exists) {
        _userAccount = UserAccount.fromFirestore(results[0]);
      }
      if (results[1].exists) {
        _userProfile = UserProfile.fromFirestore(results[1]);

        // Fixed: Removed unused local variable 'prefs' and utilized userAccount for visibility logic
        if (_userAccount != null && _userAccount!.preferences.containsKey('socialButtons')) {
          _socialButtonVisibility = Map<String, bool>.from(_userAccount!.preferences['socialButtons']);
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
      await FirebaseFirestore.instance.collection('Users').doc(_user!.uid).update({
        'preferences.socialButtons': _socialButtonVisibility
      });
    } catch (_) {}
  }
}