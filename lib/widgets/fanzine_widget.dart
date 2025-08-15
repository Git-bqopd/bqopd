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

  // Page controller for the tabbed view
  final PageController _pageController = PageController();
  int _currentPage = 0; // To track the current page

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
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.uid).get();
        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setStateIfMounted(() { _username = data['username'] ?? 'N/A'; });
        } else if (mounted) {
          print("User document not found for ${currentUser!.uid}");
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
    _pageController.dispose(); // Dispose the controller
    super.dispose();
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).primaryColorDark,
    );
    final borderRadius = BorderRadius.circular(12.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1B255),
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.all(16.0), // Consistent padding
          child: _isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Top Row: Profile Link ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const Text(
                          'profile: ',
                          style: TextStyle(fontSize: 16),
                        ),
                        RichText(
                          text: TextSpan(
                            text: _username,
                            style: linkStyle,
                            recognizer: TapGestureRecognizer()
                              ..onTap = goToProfilePage,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20), // Spacing

                    // --- Second Row: Tab Navigation ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTab('indicia', 0),
                        _buildTabSeparator(),
                        _buildTab('creators', 1),
                        _buildTabSeparator(),
                        _buildTab('stats', 2),
                      ],
                    ),
                    const SizedBox(height: 10), // Spacing

                    // --- Third Row: PageView ---
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (index) {
                          setState(() {
                            _currentPage = index;
                          });
                        },
                        children: const [
                          Center(child: Text('This is the indicia page.')),
                          Center(child: Text('This is the creators page.')),
                          Center(child: Text('This is the stats page.')),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // --- Helper to build a tab ---
  Widget _buildTab(String text, int index) {
    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: _currentPage == index ? FontWeight.bold : FontWeight.normal,
          color: _currentPage == index ? Colors.black : Colors.black54,
        ),
      ),
    );
  }

    // --- Helper for tab separator ---
  Widget _buildTabSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: Text('|', style: TextStyle(fontSize: 16, color: Colors.black54)),
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
