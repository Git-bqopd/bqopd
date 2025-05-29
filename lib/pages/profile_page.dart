import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/profile_widget.dart';

class ProfilePage extends StatefulWidget {
  final String? userId; // Document ID from 'Users' collection (currently email)

  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  String? _error;
  String _username = 'N/A';
  String _profileUserDocId = ''; // The document ID used to fetch from Users (email)
  String _profileUserUid = ''; // The UID of the profile user, for ProfileWidget

  @override
  void initState() {
    super.initState();
    _loadPageData();
  }

  Future<void> _loadPageData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (widget.userId != null) {
      _profileUserDocId = widget.userId!;
    } else if (currentUser != null) {
      _profileUserDocId = currentUser.email!; // Default to current user's email
    } else {
      if (mounted) {
        setState(() {
          _error = "No user specified and not logged in.";
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(_profileUserDocId) // Assuming _profileUserDocId is the email
          .get();

      if (mounted) {
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          _username = data['username'] ?? 'N/A';
          
          // IMPORTANT ASSUMPTION: 'Users' doc (keyed by email) must contain the user's UID.
          // If 'uid' field doesn't exist, ProfileWidget fanzine fetching will fail for other users.
          _profileUserUid = data['uid'] as String? ?? ''; 

          if (_profileUserUid.isEmpty) {
            // If viewing current user's profile AND their Users doc doesn't have UID yet
            if (widget.userId == null && currentUser != null && _profileUserDocId == currentUser.email) {
               _profileUserUid = currentUser.uid; // Fallback to current user's UID directly
               print("Warning: 'uid' field missing in Users doc for $_profileUserDocId. Using current user's UID as fallback.");
            } else {
              // This is a problem if viewing another user and their UID is missing.
              print("Error: 'uid' field missing in Users doc for $_profileUserDocId. Fanzine list may not work correctly.");
              _error = "User profile data is incomplete (missing UID).";
              // For now, we might still proceed but ProfileWidget will likely fail to show fanzines
              // Or, we could set _profileUserUid to _profileUserDocId if that's how fanzines are keyed for some reason
            }
          }

          setState(() {
            _isLoading = false;
          });

        } else {
          setState(() {
            _error = "User profile not found for ID: $_profileUserDocId";
            _isLoading = false;
            _username = 'N/A';
          });
        }
      }
    } catch (e) {
      print("Error loading user data for ProfilePage: $e");
      if (mounted) {
        setState(() {
          _error = "Failed to load profile: ${e.toString()}";
          _isLoading = false;
          _username = 'N/A';
        });
      }
    }
  }
  
  bool get _isCurrentUserProfile {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false; // Not logged in, so can't be "current user's profile"
    if (widget.userId != null) { // A specific user ID was passed
      return widget.userId == currentUser.email; // It's current user if passed ID matches logged-in user's email
    }
    return true; // No userId passed, defaults to current user
  }


  @override
  Widget build(BuildContext context) {
    String appBarTitle = _isCurrentUserProfile ? "My Profile" : (_username != 'N/A' ? "$_username's Profile" : "Profile");

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
        ),
      );
    }

    if (_profileUserUid.isEmpty && _profileUserDocId.isNotEmpty) {
        // This case implies we resolved a document ID (email) but couldn't get a UID for ProfileWidget.
        // This is problematic especially if viewing another user.
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Cannot display profile: User UID not found for $_profileUserDocId. ProfileWidget requires UID for fanzines.",
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        );
    }


    // The GridView from the original ProfilePage
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(8.0),
      mainAxisSpacing: 8.0,
      crossAxisSpacing: 8.0,
      childAspectRatio: 5 / 8, // Aspect ratio from original ProfilePage
      children: <Widget>[
        Container( // Container for ProfileWidget, from original ProfilePage
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: ProfileWidget(
              userId: _profileUserUid, // Pass the UID here
              username: _username,
            ),
          ),
        ),
        // Placeholder images from original ProfilePage (can be removed or kept as desired)
        _buildImagePlaceholder(Colors.blueGrey, 'Image 1'),
        _buildImagePlaceholder(Colors.teal, 'Image 2'),
        _buildImagePlaceholder(Colors.amber, 'Image 3'),
        _buildImagePlaceholder(Colors.deepOrange, 'Image 4'),
        _buildImagePlaceholder(Colors.purple, 'Image 5'),
      ],
    );
  }

  // Helper widget for image placeholders (from original ProfilePage)
  Widget _buildImagePlaceholder(Color color, String text) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
