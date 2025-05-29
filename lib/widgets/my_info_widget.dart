import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart'; // Required for TapGestureRecognizer
import 'package:flutter/material.dart';
// Import the pages to navigate to
import '../pages/profile_page.dart'; // <<< CHECK THIS PATH
import '../pages/edit_info_page.dart'; // <<< CHECK THIS PATH
import '../pages/create_fanzine_page.dart'; // <<< ADD THIS IMPORT
import '../pages/fanzine_reader_page.dart'; // <<< ADD THIS IMPORT FOR READER PAGE

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
  bool _isLoading = true; // For user profile data
  String? _errorMessage;
  Stream<QuerySnapshot>? _userFanzinesStream; // Stream for fanzines

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _initFanzinesStream();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = null; }); // Handles loading for user data part

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
        if (mounted) { setState(() { _errorMessage = "Error loading profile data."; }); }
      } finally {
        if (mounted) { setState(() { _isLoading = false; }); }
      }
    } else {
      print("Error: No current user found for profile data.");
      if (mounted) { setState(() { _errorMessage = "Not logged in."; _isLoading = false; }); }
    }
  }

  void _initFanzinesStream() {
    if (currentUser != null) {
      setState(() { 
        _userFanzinesStream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('authorID', isEqualTo: currentUser!.uid)
            .orderBy('createdAt', descending: true)
            .snapshots();
      });
      print("Fanzine stream initialized for user: ${currentUser!.uid}");
    } else {
      print("No user logged in, fanzine stream not initialized.");
    }
  }

  String _buildFormattedAddress() {
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
              Expanded(
                child: Column( 
                  crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Username: $_username'), const SizedBox(height: 4), Text('Email: $_email'), const SizedBox(height: 12),
                    if (_buildFormattedAddress().isNotEmpty) ...[ const Text('Address:', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(_buildFormattedAddress()), ]
                    else ... [ const Text('Address: Not Provided'), ]
                  ],
                ),
              ),
              const SizedBox(width: 20),

              // --- Right Side: Action Links ---
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // *** Link 1: View Profile ***
                  RichText( text: TextSpan( text: '[view profile]', style: linkStyle, recognizer: TapGestureRecognizer() ..onTap = () {
                    print('View Profile tapped');
                    Navigator.push( context, MaterialPageRoute(builder: (context) => const ProfilePage()), ); // Navigates to ProfilePage
                  }, ), ),
                  const SizedBox(height: 10),

                  // *** Link 2: Edit Info ***
                  RichText( text: TextSpan( text: '[edit info]', style: linkStyle, recognizer: TapGestureRecognizer() ..onTap = () {
                    print('Edit info tapped');
                    // Ensure EditInfoPage is defined and imported correctly
                    Navigator.push( context, MaterialPageRoute(builder: (context) => const EditInfoPage()), ); // Navigates to EditInfoPage
                  }, ), ),
                  const SizedBox(height: 10),

                  // *** Link 3: Upload Image ***
                  RichText( text: TextSpan( text: '[upload image]', style: linkStyle, recognizer: TapGestureRecognizer() ..onTap = () {
                    print('Upload image tapped (placeholder)');
                    ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Upload not implemented yet.')), );
                  }, ), ),
                  const SizedBox(height: 10), // Add some space

                  // *** Link 4: Create Fanzine ***
                  RichText( text: TextSpan( text: '[create fanzine]', style: linkStyle, recognizer: TapGestureRecognizer() ..onTap = () {
                    print('Create fanzine tapped');
                    Navigator.push( context, MaterialPageRoute(builder: (context) => const CreateFanzinePage()), ); // Navigates to CreateFanzinePage
                  }, ), ),
                ],
              ),
            ],
          ),
        ),
      ),
      // Fanzine List Section (Added below the main Row)
      // This needs to be outside the Row if it's a new section, or integrated differently.
      // For now, let's assume MyInfoWidget might be wrapped in a Column in its parent page (MyInfoPage)
      // and this StreamBuilder will be part of that column.
      // Given the current structure of MyInfoWidget (it IS the content of a cell),
      // it's better to integrate the fanzine list within its existing build method,
      // perhaps below the user details and links, if space allows, or make the MyInfoWidget itself scrollable.

      // Let's adjust MyInfoWidget to be a Column itself, containing the profile info row AND the fanzine list.
    );
  }


  // We need to adjust the main build method to return a Column
  // where the first child is the existing profile info Row,
  // and the second child is the Fanzine list section.

  // The previous build method's content will be moved into a helper for the profile section.
  // Then, the main build method will be a Column.

  // Let's re-think this. The original request was to modify MyInfoWidget.
  // MyInfoPage is already a SingleChildScrollView with a Column.
  // MyInfoWidget is placed in an AspectRatio container.
  // So, adding a list directly into MyInfoWidget might overflow if not handled carefully.

  // Option 1: Make MyInfoWidget itself scrollable (if it grows too large).
  // Option 2: Display a limited number of fanzines or a link to a "My Fanzines" page.

  // For this task, let's display it directly within MyInfoWidget, below the links.
  // The parent (MyInfoPage) is already scrollable.
  // We'll add the fanzine list to the Column that holds the action links.
  // This might make the right side very long.

  // A better approach for MyInfoWidget:
  // Keep the profile info and links compact.
  // The fanzine list should ideally be a separate section in MyInfoPage, below MyInfoWidget.

  // Let's assume the task implies MyInfoWidget should expand to show fanzines.
  // We will modify the main build method of MyInfoWidget.
  // The current structure is a Container -> ClipRRect -> Padding -> Row.
  // We can change the Row to a Column, where the first item is the Row of profile data & links,
  // and the second item is the fanzine list.

} // This closes _MyInfoWidgetState. Let's move the fanzine list integration into the main build method.

// To do this cleanly, I'll need to restructure the build method of _MyInfoWidgetState.

// --- Private Fanzine List Item Widget ---
// (Will be defined inside _MyInfoWidgetState or as a separate file later)


// The change needs to happen within the existing build method.
// I will add the StreamBuilder within the Padding, below the Row of user info and links.
// So, the Padding's child will become a Column.

class _FanzineListItem extends StatelessWidget {
  final QueryDocumentSnapshot fanzineDoc;

  const _FanzineListItem({required this.fanzineDoc});

  @override
  Widget build(BuildContext context) {
    final data = fanzineDoc.data() as Map<String, dynamic>;
    final String title = data['title'] ?? 'Untitled';
    final String? coverImageURL = data['coverImageURL'];
    final String fanzineId = fanzineDoc.id;

    return InkWell(
      onTap: () {
        print("Tapped on Fanzine: $title (ID: $fanzineId)");
        // TODO: Navigate to fanzine reader page
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tapped on $title. Navigation not implemented yet.')),
        );
      },
      child: Card(
        elevation: 2.0,
        clipBehavior: Clip.antiAlias, // Ensures image corners are rounded with the card
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: (coverImageURL != null && coverImageURL.isNotEmpty)
                  ? Image.network(
                      coverImageURL,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 40)),
                        );
                      },
                    )
                  : Container( // Placeholder if no cover image
                      color: Colors.grey[200],
                      child: const Center(child: Icon(Icons.book, color: Colors.grey, size: 40)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
