import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart'; // Required for TapGestureRecognizer
import 'package:flutter/material.dart';
// Import the pages to navigate to
import '../pages/profile_page.dart'; // <<< CHECK THIS PATH
import '../pages/edit_info_page.dart'; // <<< CHECK THIS PATH
import 'image_upload_modal.dart'; // Import the modal

class MyInfoWidget extends StatefulWidget {
  const MyInfoWidget({super.key});

  @override
  State<MyInfoWidget> createState() => _MyInfoWidgetState();
}

class _MyInfoWidgetState extends State<MyInfoWidget> {
  // All logic and state variables remain the same as v3
  final User? currentUser = FirebaseAuth.instance.currentUser;
  String _username = ''; String _email = ''; String _firstName = '';
  String _lastName = ''; String _street1 = ''; String _street2 = '';
  String _city = ''; String _stateName = ''; String _zipCode = '';
  String _country = '';
  bool _isLoading = true; String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // ... load user data logic ...
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    if (currentUser != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.email).get();
        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _email = currentUser!.email ?? ''; _username = data['username'] ?? '';
            _firstName = data['firstName'] ?? ''; _lastName = data['lastName'] ?? '';
            _street1 = data['street1'] ?? ''; _street2 = data['street2'] ?? '';
            _city = data['city'] ?? ''; _stateName = data['state'] ?? '';
            _zipCode = data['zipCode'] ?? ''; _country = data['country'] ?? '';
          });
        } else if (mounted) {
          setState(() { _email = currentUser!.email ?? 'N/A'; _errorMessage = "Profile data not found."; });
        }
      } catch (e) {
        print("Error loading user data: $e");
        if (mounted) { setState(() { _errorMessage = "Error loading data."; }); }
      } finally { if (mounted) { setState(() { _isLoading = false; }); } }
    } else {
      print("Error: No current user found.");
      if (mounted) { setState(() { _errorMessage = "Not logged in."; _isLoading = false; }); }
    }
  }

  String _buildFormattedAddress() {
    // ... address formatting logic ...
    List<String> parts = [];
    if (_firstName.isNotEmpty || _lastName.isNotEmpty) { parts.add('$_firstName $_lastName'.trim()); }
    if (_street1.isNotEmpty) parts.add(_street1); if (_street2.isNotEmpty) parts.add(_street2);
    String cityStateZip = '$_city, $_stateName $_zipCode'.trim();
    cityStateZip = cityStateZip.replaceAll(RegExp(r'^,\s*'), '').replaceAll(RegExp(r'\s*,\s*$'), '').trim();
    if (cityStateZip.isNotEmpty && cityStateZip != ',') parts.add(cityStateZip);
    if (_country.isNotEmpty) parts.add(_country);
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    // ... linkStyle and borderRadius definitions ...
    final linkStyle = TextStyle( fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark, );
    final borderRadius = BorderRadius.circular(12.0);

    return Container(
      // ... Container decoration ...
      decoration: BoxDecoration( color: const Color(0xFFF1B255), borderRadius: borderRadius, ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Left Side: Profile Info ---
              Expanded( child: Column( /* ... profile info Text widgets ... */
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Username: $_username'), const SizedBox(height: 4), Text('Email: $_email'), const SizedBox(height: 12),
                  if (_buildFormattedAddress().isNotEmpty) ...[ const Text('mailing address:', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(_buildFormattedAddress()), ]
                  else ... [ const Text('Address: Not Provided'), ]
                ],
              ),),
              const SizedBox(width: 20),

              // --- Right Side: Action Links ---
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // *** Link 1: View Profile ***
                  RichText( text: TextSpan( text: 'view profile', style: linkStyle, recognizer: TapGestureRecognizer() ..onTap = () {
                    print('View Profile tapped');
                    Navigator.push( context, MaterialPageRoute(builder: (context) => const ProfilePage()), ); // Navigates to ProfilePage
                  }, ), ),
                  const SizedBox(height: 10),

                  // *** Link 2: Edit Info ***
                  RichText( text: TextSpan( text: 'edit info', style: linkStyle, recognizer: TapGestureRecognizer() ..onTap = () {
                    print('Edit info tapped');
                    // Ensure EditInfoPage is defined and imported correctly
                    Navigator.push( context, MaterialPageRoute(builder: (context) => const EditInfoPage()), ); // Navigates to EditInfoPage
                  }, ), ),
                  const SizedBox(height: 10),

                  // *** Link 3: Upload Image ***
                  RichText(
                    text: TextSpan(
                      text: 'upload image', // Changed text
                      style: linkStyle, // Applied same style as other links
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          if (currentUser?.uid == null && currentUser?.email == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('You must be logged in to upload images.')),
                            );
                            return;
                          }
                          // Use UID if available, otherwise fallback to email for userId.
                          // Firebase UID is the preferred unique identifier for users.
                          final String userId = currentUser!.uid.isNotEmpty ? currentUser!.uid : currentUser!.email!;

                          print('Upload Image link tapped by user: $userId'); // Updated log message
                          showDialog(
                            context: context,
                            barrierDismissible: false, // User must tap button to close
                            builder: (BuildContext dialogContext) {
                              return ImageUploadModal(userId: userId);
                            },
                          ).then((success) {
                            if (success == true) {
                              // Optional: Refresh data or show a confirmation that's not a snackbar
                              print("Modal closed with success");
                            } else {
                              // Optional: Handle cancellation or failure if needed
                              print("Modal closed without explicit success");
                            }
                          });
                        },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
