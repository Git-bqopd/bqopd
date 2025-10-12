import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/button.dart'; // Assuming MyButton is here
import '../components/textfield.dart'; // Assuming MyTextField is here (used for Username)
// Import the My Info page to navigate to it
import '../pages/profile_page.dart'; // Adjust path if needed

class EditInfoWidget extends StatefulWidget {
  final String fanzineId;

  const EditInfoWidget({super.key, required this.fanzineId});

  @override
  State<EditInfoWidget> createState() => _EditInfoWidgetState();
}

class _EditInfoWidgetState extends State<EditInfoWidget> {
  // All logic (controllers, loading, saving, etc.) remains the same as v1
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Text editing controllers
  final TextEditingController userNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController bioController = TextEditingController();
  final TextEditingController street1Controller = TextEditingController();
  final TextEditingController street2Controller = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController stateController = TextEditingController();
  final TextEditingController zipController = TextEditingController();
  final TextEditingController countryController = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();

  bool _isLoadingData = true;
  bool _isSaving = false;
  String _initialUsername = "";

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // ... (load user data logic remains the same) ...
    if (!mounted) return;
    setState(() { _isLoadingData = true; });

    if (currentUser != null) {
      try {
        emailController.text = currentUser!.email ?? 'No Email Found';
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser!.email)
            .get();

        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setStateIfMounted(() {
            _initialUsername = data['username'] ?? ''; userNameController.text = _initialUsername;
            bioController.text = data['bio'] ?? '';
            street1Controller.text = data['street1'] ?? ''; street2Controller.text = data['street2'] ?? '';
            cityController.text = data['city'] ?? ''; stateController.text = data['state'] ?? '';
            zipController.text = data['zipCode'] ?? ''; countryController.text = data['country'] ?? '';
            firstNameController.text = data['firstName'] ?? ''; lastNameController.text = data['lastName'] ?? '';
          });
        } else if (mounted) {
          print("User document not found in Firestore for ${currentUser!.email}");
          setStateIfMounted(() { userNameController.text = currentUser!.displayName ?? ''; });
        }
      } catch (e) {
        print("Error loading user data: $e");
        if(mounted) { displayMessageToUser("Error loading profile: ${e.toString()}", context); }
        setStateIfMounted(() { /* set error defaults */ });
      } finally {
        setStateIfMounted(() { _isLoadingData = false; });
      }
    } else {
      print("Error: No current user found.");
      setStateIfMounted(() { _isLoadingData = false; });
    }
  }

  Future<void> saveProfile() async {
    // ... (save profile logic remains the same) ...
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    setStateIfMounted(() { _isSaving = true; });

    try {
      if (currentUser != null) {
        final Map<String, dynamic> dataToUpdate = { /* ... data map ... */
          'username': userNameController.text.trim(), 'bio': bioController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
          'firstName': firstNameController.text.trim(), 'lastName': lastNameController.text.trim(),
          'street1': street1Controller.text.trim(), 'street2': street2Controller.text.trim(),
          'city': cityController.text.trim(), 'state': stateController.text.trim(),
          'zipCode': zipController.text.trim(), 'country': countryController.text.trim(),
        };
        await FirebaseFirestore.instance.collection('Users').doc(currentUser!.email).set(dataToUpdate, SetOptions(merge: true));
        _initialUsername = userNameController.text.trim();
        if(mounted) { displayMessageToUser("Profile Saved!", context); }
      } else { if(mounted) { displayMessageToUser("Error: No user logged in.", context); } }
    } catch (e) {
      print("Error saving profile: $e");
      if(mounted) { displayMessageToUser("Error saving profile: ${e.toString()}", context); }
    } finally {
      setStateIfMounted(() { _isSaving = false; });
    }
  }

  void goToMyInfoPage() {
    // ... (navigation logic remains the same) ...
    Navigator.push( context, MaterialPageRoute(builder: (context) => const ProfilePage()), );
  }

  void logout() async {
    // ... (logout logic remains the same) ...
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) { Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil( '/login_or_register', (Route<dynamic> route) => false, ); }
    } catch (e) {
      print("Error logging out: $e");
      if (mounted) { displayMessageToUser("Error logging out: ${e.toString()}", context); }
    }
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) { setState(fn); }
  }

  @override
  void dispose() {
    // ... (dispose logic remains the same) ...
    userNameController.dispose(); emailController.dispose(); bioController.dispose();
    street1Controller.dispose(); street2Controller.dispose(); cityController.dispose();
    stateController.dispose(); zipController.dispose(); countryController.dispose();
    firstNameController.dispose(); lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration defaultDecoration = InputDecoration( /* ... decoration ... */
      enabledBorder: OutlineInputBorder( borderSide: BorderSide(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8), ),
      focusedBorder: OutlineInputBorder( borderSide: BorderSide(color: Theme.of(context).primaryColor), borderRadius: BorderRadius.circular(8), ),
      fillColor: Colors.white, filled: true, contentPadding: const EdgeInsets.all(15), hintStyle: TextStyle(color: Colors.grey[500]),
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
          padding: const EdgeInsets.all(25.0),
          child: _isLoadingData
              ? const Center(child: CircularProgressIndicator())
          // *** ADDED SingleChildScrollView here ***
              : SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              // We might not need min size anymore if scroll view handles it
              // mainAxisSize: MainAxisSize.min,
              children: [
                // --- Header ---
                Text(
                  'edit your profile',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColorDark,
                  ),
                ),
                const SizedBox(height: 20),

                // --- All the TextFields ---
                // (Code for TextFields remains exactly the same)
                TextField( controller: emailController, enabled: false, decoration: defaultDecoration.copyWith( hintText: "email", fillColor: Colors.grey[200], ), style: TextStyle(color: Colors.grey[700]), ), const SizedBox(height: 10),
                MyTextField( controller: userNameController, hintText: "Username", obscureText: false, ), const SizedBox(height: 10),
                TextField( controller: bioController, maxLines: 3, decoration: defaultDecoration.copyWith( hintText: "Bio (tell us about yourself!)", ), keyboardType: TextInputType.multiline, ), const SizedBox(height: 25),
                Text( 'mailing address', style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark, ), ), const SizedBox(height: 15),
                TextField( controller: firstNameController, decoration: defaultDecoration.copyWith(hintText: "first Name"), keyboardType: TextInputType.name, textCapitalization: TextCapitalization.words, ), const SizedBox(height: 10),
                TextField( controller: lastNameController, decoration: defaultDecoration.copyWith(hintText: "last Name"), keyboardType: TextInputType.name, textCapitalization: TextCapitalization.words, ), const SizedBox(height: 10),
                TextField( controller: street1Controller, decoration: defaultDecoration.copyWith(hintText: "street address 1"), keyboardType: TextInputType.streetAddress, ), const SizedBox(height: 10),
                TextField( controller: street2Controller, decoration: defaultDecoration.copyWith(hintText: "street address 2 (Optional)"), keyboardType: TextInputType.streetAddress, ), const SizedBox(height: 10),
                TextField( controller: cityController, decoration: defaultDecoration.copyWith(hintText: "city"), keyboardType: TextInputType.text, textCapitalization: TextCapitalization.words, ), const SizedBox(height: 10),
                TextField( controller: stateController, decoration: defaultDecoration.copyWith(hintText: "state"), keyboardType: TextInputType.text, textCapitalization: TextCapitalization.words, ), const SizedBox(height: 10),
                TextField( controller: zipController, decoration: defaultDecoration.copyWith(hintText: "zip / postal code"), keyboardType: TextInputType.streetAddress, ), const SizedBox(height: 25),

                // --- Buttons ---
                // (Code for Buttons remains exactly the same)
                MyButton( text: _isSaving ? "saving..." : "save profile", onTap: _isSaving ? null : saveProfile, ), const SizedBox(height: 15),
                MyButton( text: "my info", onTap: goToMyInfoPage, ), const SizedBox(height: 15),
                MyButton( text: "logout", onTap: logout, ),

                // *** REMOVED Spacer ***
                // const Spacer(), // Not needed with SingleChildScrollView
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Helper function to display messages (ensure it's accessible)
void displayMessageToUser(String message, BuildContext context) {
  // ... (display message logic remains the same) ...
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(message), duration: const Duration(seconds: 3), ), );
}
