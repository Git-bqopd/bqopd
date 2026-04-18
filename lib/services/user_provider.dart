import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fanzine.dart';

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

  User? get user => _user;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, bool> get socialButtonVisibility => _socialButtonVisibility;
  bool get isLoggedIn => _user != null;
  String? get currentUserId => _user?.uid;
  bool get isLoading => _isLoading;

  /// Moderator / Superuser: Can edit everything.
  bool get isModerator {
    if (_userProfile == null) return false;
    final role = _userProfile!['role'];
    return role == 'admin' || role == 'moderator';
  }

  /// Curator: Access to archival pipelines (OCR, Entity extraction).
  bool get isCurator {
    if (_userProfile == null) return false;
    if (isModerator) return true;
    final role = _userProfile!['role'];
    return role == 'curator' || _userProfile!['isCurator'] == true;
  }

  /// Checks if the current user has permission to edit a specific Fanzine.
  bool canEditFanzine(Fanzine fanzine) {
    if (!isLoggedIn) return false;
    if (isModerator) return true;
    if (fanzine.ownerId == _user!.uid) return true;
    if (fanzine.editors.contains(_user!.uid)) return true;
    return false;
  }

  Future<void> _fetchUserProfile(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (doc.exists) {
        _userProfile = doc.data() as Map<String, dynamic>;
        if (_userProfile!.containsKey('preferences')) {
          final prefs = _userProfile!['preferences'] as Map<String, dynamic>;
          if (prefs.containsKey('socialButtons')) {
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

  void toggleSocialButtonVisibility(String toolId) {
    final currentVal = _socialButtonVisibility[toolId] ?? true;
    _socialButtonVisibility[toolId] = !currentVal;
    notifyListeners();
    _savePreferences();
  }

  Future<void> _savePreferences() async {
    if (_user == null) return;
    try {
      await FirebaseFirestore.instance.collection('Users').doc(_user!.uid).set({
        'preferences': { 'socialButtons': _socialButtonVisibility }
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}