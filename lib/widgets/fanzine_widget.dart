import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart'; // For TapGestureRecognizer
import 'package:flutter/material.dart';
// Import the My Info page to navigate to it
import '../pages/profile_page.dart'; // Adjust path if needed

// This widget now primarily displays the username and a link to more info.
// It includes its own background color and rounded corners.
class FanzineWidget extends StatefulWidget {
  const FanzineWidget({super.key});

  @override
  State<FanzineWidget> createState() => _FanzineWidgetState();
}

class _FanzineWidgetState extends State<FanzineWidget> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Simplified state: only need username and loading state
  String _username = '';
  bool _isLoadingData = true;
  String? _errorMessage; // Optional: for error display

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // --- Simplified Load User Data Method ---
  Future<void> _loadUserData() async {
    // ... (load user data logic remains the same) ...
    if (!mounted) return;
    setState(() { _isLoadingData = true; _errorMessage = null; });
    if (currentUser != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.email).get();
        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setStateIfMounted(() { _username = data['username'] ?? 'N/A'; });
        } else if (mounted) {
          print("User document not found for ${currentUser!.email}");
          setStateIfMounted(() { _username = 'N/A'; });
        }
      } catch (e) {
        print("Error loading username: $e");
        if(mounted) { setStateIfMounted(() { _username = 'Error'; }); }
      } finally { setStateIfMounted(() { _isLoadingData = false; }); }
    } else {
      print("Error: No current user found.");
      setStateIfMounted(() { _username = 'N/A'; _isLoadingData = false; });
    }
  }

  // Helper to avoid multiple mounted checks
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) { setState(fn); }
  }

  // --- Navigate to Profile Page Method ---
  void goToProfilePage() {
    Navigator.push( context, MaterialPageRoute(builder: (context) => const ProfilePage()), );
  }


  @override
  void dispose() {
    super.dispose();
  }

  // --- Simplified Build Method ---
  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle( fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark, );
    final borderRadius = BorderRadius.circular(12.0); // Consistent radius

    // *** ADDED Container for background and rounded corners ***
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1B255), // Set background color
        borderRadius: borderRadius,
      ),
      // *** ADDED ClipRRect to ensure content respects corners ***
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Center( // Center the content vertically and horizontally
          child: Padding(
            padding: const EdgeInsets.all(25.0), // Keep some padding
            child: _isLoadingData
                ? const CircularProgressIndicator()
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Display Username
                Text(
                  'username: $_username',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20), // Spacing

                // Link to Profile Page
                RichText(
                  text: TextSpan(
                    text: 'profile', // Link text
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = goToProfilePage, // Navigate on tap
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Helper function (can be removed if not used for errors)
void displayMessageToUser(String message, BuildContext context) {
  // ... (display message logic remains the same) ...
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(message), duration: const Duration(seconds: 3), ), );
}
