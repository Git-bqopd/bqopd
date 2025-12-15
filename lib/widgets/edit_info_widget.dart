import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:go_router/go_router.dart';
import '../components/button.dart';
import '../components/textfield.dart';
import '../pages/profile_page.dart';
import '../services/username_service.dart';

// -----------------------------------------------------------------------------
// TODO: PASTE YOUR NEW ANDROID API KEY HERE
// This key should be restricted to "Android apps" in Cloud Console.
// On Web, the SDK automatically uses the key from index.html (which should be restricted to Websites).
// -----------------------------------------------------------------------------
const String kGoogleApiKeyMobile = 'AIzaSyDVZREk4WuVoGJhVj9I0PmFCb8IQcSA6GQ';

class EditInfoWidget extends StatefulWidget {
  const EditInfoWidget({super.key});

  @override
  State<EditInfoWidget> createState() => _EditInfoWidgetState();
}

class _EditInfoWidgetState extends State<EditInfoWidget> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Google Places SDK
  late final FlutterGooglePlacesSdk _places;

  final TextEditingController userNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController bioController = TextEditingController();

  // Address Controllers
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

  // Track if the user has manually edited their username
  bool _isUsernameManuallyEdited = false;

  @override
  void initState() {
    super.initState();

    // Initialize Places SDK
    // Pass the Android key here. On Web, the package ignores this string
    // and uses the key from the <script> tag in index.html.
    _places = FlutterGooglePlacesSdk(kGoogleApiKeyMobile);

    _loadUserData();

    // Add listeners for auto-generating username
    firstNameController.addListener(_updateDefaultUsername);
    stateController.addListener(_updateDefaultUsername);
  }

  @override
  void dispose() {
    firstNameController.removeListener(_updateDefaultUsername);
    stateController.removeListener(_updateDefaultUsername);

    userNameController.dispose();
    emailController.dispose();
    bioController.dispose();
    street1Controller.dispose();
    street2Controller.dispose();
    cityController.dispose();
    stateController.dispose();
    zipController.dispose();
    countryController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    super.dispose();
  }

  /// Logic to create "Kevin-from-WI" automatically
  void _updateDefaultUsername() {
    if (_isUsernameManuallyEdited) return;

    final name = firstNameController.text.trim();
    final state = stateController.text.trim();

    if (name.isNotEmpty && state.isNotEmpty) {
      String generated = "$name-from-$state";
      // Normalize: lowercase, no special chars except hyphens
      generated = generated.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');

      setState(() {
        userNameController.text = generated;
      });
    }
  }

  /// Opens the Address Search Modal
  void _openAddressSearch() async {
    // We use 'dynamic' because the result can be AutocompletePrediction (from Google)
    // OR it can be a String (if user typed manual text)
    final dynamic result = await showDialog(
      context: context,
      builder: (context) => _AddressSearchDialog(places: _places),
    );

    if (result is AutocompletePrediction) {
      if (result.placeId.isNotEmpty) {
        _fetchAndFillAddress(result.placeId);
      }
    } else if (result is String && result.isNotEmpty) {
      // Manual Entry Case
      setState(() {
        street1Controller.text = result;
        // We do NOT clear City/State/Zip here, because for a PO Box,
        // the user likely still needs to enter those manually.
      });
    }
  }

  /// Fetches place details and fills the form
  Future<void> _fetchAndFillAddress(String placeId) async {
    setState(() => _isLoadingData = true);
    try {
      final response = await _places.fetchPlace(
        placeId,
        fields: [
          PlaceField.AddressComponents,
          PlaceField.Location,
        ],
      );

      final place = response.place;
      if (place == null || place.addressComponents == null) return;

      String streetNum = '';
      String route = '';
      String city = '';
      String state = '';
      String zip = '';
      String country = '';

      for (var c in place.addressComponents!) {
        final types = c.types;
        // Note: The property is 'name' in this package, not 'longName'
        // 'shortName' is available for abbreviated forms (like state codes)
        if (types.contains('street_number')) streetNum = c.name;
        if (types.contains('route')) route = c.name;
        if (types.contains('locality') || types.contains('postal_town')) city = c.name;
        if (types.contains('administrative_area_level_1')) state = c.shortName ?? c.name; // "WI"
        if (types.contains('postal_code')) zip = c.name;
        if (types.contains('country')) country = c.name;
      }

      setState(() {
        street1Controller.text = "$streetNum $route".trim();
        cityController.text = city;
        stateController.text = state; // Triggers _updateDefaultUsername!
        zipController.text = zip;
        countryController.text = country;
      });

    } catch (e) {
      displayMessageToUser("Error fetching address details: $e", context);
    } finally {
      setState(() => _isLoadingData = false);
    }
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() { _isLoadingData = true; });

    if (currentUser != null) {
      try {
        emailController.text = currentUser!.email ?? 'No Email Found';

        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser!.uid)
            .get();

        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _initialUsername = data['username'] ?? '';
            userNameController.text = _initialUsername;
            if (_initialUsername.isNotEmpty) {
              _isUsernameManuallyEdited = true;
            }

            bioController.text = data['bio'] ?? '';
            street1Controller.text = data['street1'] ?? '';
            street2Controller.text = data['street2'] ?? '';
            cityController.text = data['city'] ?? '';
            stateController.text = data['state'] ?? '';
            zipController.text = data['zipCode'] ?? '';
            countryController.text = data['country'] ?? '';
            firstNameController.text = data['firstName'] ?? '';
            lastNameController.text = data['lastName'] ?? '';
          });
        }
      } catch (e) {
        if(mounted) displayMessageToUser("Error loading profile", context);
      } finally {
        if(mounted) setState(() { _isLoadingData = false; });
      }
    } else {
      if(mounted) setState(() { _isLoadingData = false; });
    }
  }

  Future<void> saveProfile() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    setState(() { _isSaving = true; });

    try {
      if (currentUser != null) {
        final finalUsername = normalizeHandle(userNameController.text);

        final Map<String, dynamic> dataToUpdate = {
          'username': finalUsername,
          'bio': bioController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
          'firstName': firstNameController.text.trim(),
          'lastName': lastNameController.text.trim(),
          'street1': street1Controller.text.trim(),
          'street2': street2Controller.text.trim(),
          'city': cityController.text.trim(),
          'state': stateController.text.trim(),
          'zipCode': zipController.text.trim(),
          'country': countryController.text.trim(),
          'email': currentUser!.email,
          'uid': currentUser!.uid,
        };

        await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser!.uid)
            .set(dataToUpdate, SetOptions(merge: true));

        if (finalUsername.isNotEmpty && finalUsername != _initialUsername) {
          await claimHandle(finalUsername);
        }

        _initialUsername = finalUsername;
        userNameController.text = finalUsername;

        if(mounted) displayMessageToUser("Profile Saved!", context);
      }
    } catch (e) {
      if(mounted) displayMessageToUser("Error saving: $e", context);
    } finally {
      if(mounted) setState(() { _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration defaultDecoration = InputDecoration(
      enabledBorder: OutlineInputBorder( borderSide: BorderSide(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8), ),
      focusedBorder: OutlineInputBorder( borderSide: BorderSide(color: Theme.of(context).primaryColor), borderRadius: BorderRadius.circular(8), ),
      fillColor: Colors.white, filled: true, contentPadding: const EdgeInsets.all(15), hintStyle: TextStyle(color: Colors.grey[500]),
      isDense: true,
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
              ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit Your Profile', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark)),
              const SizedBox(height: 20),

              // --- Identity ---
              _buildSectionLabel('Identity'),
              TextField( controller: emailController, enabled: false, decoration: defaultDecoration.copyWith(hintText: "email", fillColor: Colors.grey[200]), style: TextStyle(color: Colors.grey[700]) ),
              const SizedBox(height: 10),

              TextField(
                controller: userNameController,
                decoration: defaultDecoration.copyWith(hintText: "Username (e.g. kevin-from-wi)"),
                onChanged: (val) => _isUsernameManuallyEdited = true,
              ),
              if (!_isUsernameManuallyEdited && firstNameController.text.isNotEmpty && stateController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                  child: Text("Auto-generating handle...", style: TextStyle(fontSize: 12, color: Colors.indigo.shade800, fontStyle: FontStyle.italic)),
                ),

              const SizedBox(height: 10),
              TextField( controller: bioController, maxLines: 3, decoration: defaultDecoration.copyWith(hintText: "Bio (tell us about yourself!)"), keyboardType: TextInputType.multiline ),
              const SizedBox(height: 25),

              // --- Mailing Address ---
              _buildSectionLabel('Mailing Address'),
              // Removed old search button row from here

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(child: TextField(controller: firstNameController, decoration: defaultDecoration.copyWith(hintText: "First Name"), textCapitalization: TextCapitalization.words)),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: lastNameController, decoration: defaultDecoration.copyWith(hintText: "Last Name"), textCapitalization: TextCapitalization.words)),
                ],
              ),
              const SizedBox(height: 10),

              // Street Address Button (Triggers Search) - MOVED HERE
              GestureDetector(
                onTap: _openAddressSearch,
                child: AbsorbPointer(
                  child: TextField(
                    controller: street1Controller,
                    decoration: defaultDecoration.copyWith(
                      hintText: "Tap to search address...",
                      prefixIcon: const Icon(Icons.location_on_outlined, color: Colors.indigo),
                      filled: true,
                      fillColor: Colors.indigo.withOpacity(0.05),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              TextField( controller: street2Controller, decoration: defaultDecoration.copyWith(hintText: "Apt / Suite / Other") ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(flex: 2, child: TextField(controller: cityController, decoration: defaultDecoration.copyWith(hintText: "City"))),
                  const SizedBox(width: 10),
                  Expanded(flex: 1, child: TextField(controller: stateController, decoration: defaultDecoration.copyWith(hintText: "State"))),
                  const SizedBox(width: 10),
                  Expanded(flex: 1, child: TextField(controller: zipController, decoration: defaultDecoration.copyWith(hintText: "Zip"))),
                ],
              ),
              const SizedBox(height: 10),
              TextField( controller: countryController, decoration: defaultDecoration.copyWith(hintText: "Country") ),

              const SizedBox(height: 30),
              MyButton(text: _isSaving ? "Saving..." : "Save Profile", onTap: _isSaving ? null : saveProfile),
              const SizedBox(height: 15),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (_initialUsername.isNotEmpty) {
                          context.pushNamed('shortlink', pathParameters: {'code': _initialUsername});
                        } else {
                          context.push('/profile');
                        }
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white), padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text("View Public Profile"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if(mounted) context.go('/login');
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.black87, backgroundColor: Colors.white.withOpacity(0.3), side: BorderSide.none, padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text("Logout"),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark)),
    );
  }
}

// --- Internal Search Dialog ---
class _AddressSearchDialog extends StatefulWidget {
  final FlutterGooglePlacesSdk places;
  const _AddressSearchDialog({required this.places});

  @override
  State<_AddressSearchDialog> createState() => _AddressSearchDialogState();
}

class _AddressSearchDialogState extends State<_AddressSearchDialog> {
  List<AutocompletePrediction> _predictions = [];
  Timer? _debounce;
  final TextEditingController _controller = TextEditingController();

  bool _isSearching = false;
  String? _errorMessage;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Clear state if empty
    if (query.isEmpty) {
      setState(() {
        _predictions = [];
        _isSearching = false;
        _errorMessage = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        _isSearching = true;
        _errorMessage = null;
      });

      try {
        final response = await widget.places.findAutocompletePredictions(query);
        setState(() {
          _predictions = response.predictions;
          _isSearching = false;
        });
      } catch (e) {
        setState(() {
          _isSearching = false;
          _errorMessage = e.toString();
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 60, left: 16, right: 16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 400),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "Start typing address...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
              // ALLOW ENTER KEY to use the text immediately
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  Navigator.pop(context, val.trim());
                }
              },
            ),
            const SizedBox(height: 10),

            // --- Result List or Status ---
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    // 1. Error Case (Billing/API issues) -> Show Error but allow manual override
    if (_errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Error: $_errorMessage\n\n(Check API Key & Billing)",
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          if (_controller.text.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text("Use what I typed anyway"),
              onPressed: () => Navigator.pop(context, _controller.text),
            )
        ],
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. No Results (or just empty list)
    if (_predictions.isEmpty) {
      if (_controller.text.isNotEmpty) {
        // Show manual option nicely
        return ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note, color: Colors.indigo),
              title: Text('Use "${_controller.text}"'),
              subtitle: const Text("Enter address manually (bypasses search)"),
              onTap: () => Navigator.pop(context, _controller.text),
            ),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(
                  child: Text("No Google matches found.", style: TextStyle(color: Colors.grey))
              ),
            ),
          ],
        );
      }
      return const Center(child: Text("Start typing to search...", style: TextStyle(color: Colors.grey)));
    }

    // 3. Results List
    return ListView.separated(
      itemCount: _predictions.length + 1, // +1 for the manual footer option
      separatorBuilder: (c, i) => const Divider(height: 1),
      itemBuilder: (context, index) {
        // Footer Option: Always allow manual entry at the bottom of the list
        if (index == _predictions.length) {
          return ListTile(
            leading: const Icon(Icons.edit_note, color: Colors.grey),
            title: Text('Use "${_controller.text}"'),
            subtitle: const Text("Use text exactly as typed"),
            onTap: () => Navigator.pop(context, _controller.text),
          );
        }

        final item = _predictions[index];
        return ListTile(
          title: Text(item.primaryText),
          subtitle: Text(item.secondaryText ?? ''),
          leading: const Icon(Icons.location_on, color: Colors.grey),
          onTap: () => Navigator.pop(context, item),
        );
      },
    );
  }
}

// --- Helper Method ---
void displayMessageToUser(String message, BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(message), duration: const Duration(seconds: 3), ), );
}