import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import '../services/username_service.dart';
import '../env.dart';
import '../utils/script_loader.dart';
import 'image_selector_modal.dart';

/// Managed profile and personal info editor.
/// Dual-writes public identity to 'profiles' and private contact info to 'Users'.
class EditInfoWidget extends StatefulWidget {
  final String? targetUserId;

  const EditInfoWidget({super.key, this.targetUserId});

  @override
  State<EditInfoWidget> createState() => _EditInfoWidgetState();
}

class _EditInfoWidgetState extends State<EditInfoWidget> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  late final FlutterGooglePlacesSdk _places;

  final TextEditingController displayNameController = TextEditingController();
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

  final TextEditingController xHandleController = TextEditingController();
  final TextEditingController instagramHandleController = TextEditingController();
  final TextEditingController githubHandleController = TextEditingController();

  String? _profilePhotoUrl;
  bool _isLoadingData = true;
  bool _isSaving = false;
  String _initialUsername = "";
  bool _isUsernameManuallyEdited = false;

  String get _editingUid => widget.targetUserId ?? currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    loadGoogleMapsScript();

    // Select correct API key for the platform
    String apiKey = kIsWeb ? Env.googleApiKeyWeb : Env.googleApiKeyAndroid;
    _places = FlutterGooglePlacesSdk(apiKey);

    _loadData();

    firstNameController.addListener(_updateDefaultUsername);
    stateController.addListener(_updateDefaultUsername);
  }

  @override
  void dispose() {
    firstNameController.removeListener(_updateDefaultUsername);
    stateController.removeListener(_updateDefaultUsername);
    displayNameController.dispose();
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
    xHandleController.dispose();
    instagramHandleController.dispose();
    githubHandleController.dispose();
    super.dispose();
  }

  void _updateDefaultUsername() {
    if (_isUsernameManuallyEdited) return;
    final name = firstNameController.text.trim();
    final state = stateController.text.trim();
    if (name.isNotEmpty && state.isNotEmpty) {
      String generated = "$name-from-$state"
          .toLowerCase()
          .replaceAll(' ', '-')
          .replaceAll(RegExp(r'[^a-z0-9-]'), '');
      setState(() => userNameController.text = generated);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoadingData = true);

    if (_editingUid.isNotEmpty) {
      try {
        final db = FirebaseFirestore.instance;

        // 1. Load Private Account Info
        final userDoc = await db.collection('Users').doc(_editingUid).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          emailController.text = data['email'] ?? '';
          firstNameController.text = data['firstName'] ?? '';
          lastNameController.text = data['lastName'] ?? '';
          street1Controller.text = data['street1'] ?? '';
          street2Controller.text = data['street2'] ?? '';
          cityController.text = data['city'] ?? '';
          stateController.text = data['state'] ?? '';
          zipController.text = data['zipCode'] ?? '';
          countryController.text = data['country'] ?? '';
        }

        // 2. Load Public Profile Info
        final profileDoc = await db.collection('profiles').doc(_editingUid).get();
        if (profileDoc.exists) {
          final data = profileDoc.data()!;
          _initialUsername = data['username'] ?? '';
          userNameController.text = _initialUsername;
          displayNameController.text = data['displayName'] ?? '';
          bioController.text = data['bio'] ?? '';
          xHandleController.text = data['xHandle'] ?? '';
          instagramHandleController.text = data['instagramHandle'] ?? '';
          githubHandleController.text = data['githubHandle'] ?? '';
          _profilePhotoUrl = data['photoUrl'];
          if (_initialUsername.isNotEmpty) _isUsernameManuallyEdited = true;
        }
      } catch (e) {
        if (mounted) displayMessageToUser("Error loading profile", context);
      }
    }
    if (mounted) setState(() => _isLoadingData = false);
  }

  void _openAddressSearch() async {
    final dynamic result = await showDialog(
      context: context,
      builder: (context) => _AddressSearchDialog(places: _places),
    );

    if (result is AutocompletePrediction) {
      if (result.placeId.isNotEmpty) {
        _fetchAndFillAddress(result.placeId);
      }
    } else if (result is String && result.isNotEmpty) {
      setState(() {
        street1Controller.text = result;
      });
    }
  }

  Future<void> _fetchAndFillAddress(String placeId) async {
    setState(() => _isLoadingData = true);
    try {
      final response = await _places.fetchPlace(
        placeId,
        fields: [PlaceField.AddressComponents, PlaceField.Location],
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
        if (types.contains('street_number')) streetNum = c.name;
        if (types.contains('route')) route = c.name;
        if (types.contains('locality') || types.contains('postal_town')) city = c.name;
        if (types.contains('administrative_area_level_1')) state = c.shortName;
        if (types.contains('postal_code')) zip = c.name;
        if (types.contains('country')) country = c.name;
      }

      setState(() {
        street1Controller.text = "$streetNum $route".trim();
        cityController.text = city;
        stateController.text = state;
        zipController.text = zip;
        countryController.text = country;
      });
    } catch (e) {
      if (!mounted) return;
      displayMessageToUser("Error fetching address details: $e", context);
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<void> saveProfile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      if (_editingUid.isNotEmpty) {
        final db = FirebaseFirestore.instance;
        final finalUsername = normalizeHandle(userNameController.text);
        final batch = db.batch();

        // 1. Public Data (Profiles)
        final publicData = {
          'username': finalUsername,
          'displayName': displayNameController.text.trim(),
          'bio': bioController.text.trim(),
          'photoUrl': _profilePhotoUrl,
          'xHandle': xHandleController.text.trim().replaceAll('@', ''),
          'instagramHandle': instagramHandleController.text.trim().replaceAll('@', ''),
          'githubHandle': githubHandleController.text.trim().replaceAll('@', ''),
          'updatedAt': FieldValue.serverTimestamp(),
          'uid': _editingUid,
        };
        batch.set(db.collection('profiles').doc(_editingUid), publicData, SetOptions(merge: true));

        // 2. Private Data (Users)
        final privateData = {
          'firstName': firstNameController.text.trim(),
          'lastName': lastNameController.text.trim(),
          'street1': street1Controller.text.trim(),
          'street2': street2Controller.text.trim(),
          'city': cityController.text.trim(),
          'state': stateController.text.trim(),
          'zipCode': zipController.text.trim(),
          'country': countryController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
          'uid': _editingUid,
        };
        batch.set(db.collection('Users').doc(_editingUid), privateData, SetOptions(merge: true));

        await batch.commit();

        if (finalUsername.isNotEmpty && finalUsername != _initialUsername) {
          await claimHandle(finalUsername);
        }

        _initialUsername = finalUsername;
        if (mounted) displayMessageToUser("Profile Saved!", context);
      }
    } catch (e) {
      if (mounted) displayMessageToUser("Error saving: $e", context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onChangePhoto() async {
    final result = await showDialog<String>(context: context, builder: (context) => ImageSelectorModal(userId: _editingUid));
    if (result != null) setState(() => _profilePhotoUrl = result);
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration dec = InputDecoration(
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black12), borderRadius: BorderRadius.zero),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black, width: 2), borderRadius: BorderRadius.zero),
      fillColor: Colors.white, filled: true, isDense: true, contentPadding: const EdgeInsets.all(15),
    );

    final String pageTitle = widget.targetUserId != null ? 'Edit Managed Profile' : 'Edit Your Profile';

    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF1B255)),
      child: Padding(
        padding: const EdgeInsets.all(25.0),
        child: _isLoadingData
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(pageTitle,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 20),

              LayoutBuilder(builder: (context, constraints) {
                bool isNarrow = constraints.maxWidth < 600;

                Widget photoSection = GestureDetector(
                  onTap: _onChangePhoto,
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 5 / 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            border: Border.all(color: Colors.black12),
                          ),
                          child: _profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty
                              ? Image.network(_profilePhotoUrl!, fit: BoxFit.cover)
                              : const Icon(Icons.person, size: 60, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text("change photo", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                    ],
                  ),
                );

                Widget identityFields = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSectionLabel('Public Identity'),
                    TextField(controller: displayNameController, decoration: dec.copyWith(hintText: "Display Name")),
                    const SizedBox(height: 10),
                    TextField(controller: userNameController, decoration: dec.copyWith(hintText: "Username"), onChanged: (v) => _isUsernameManuallyEdited = true),
                    const SizedBox(height: 10),
                    TextField(controller: bioController, maxLines: 5, decoration: dec.copyWith(hintText: "Bio")),
                  ],
                );

                if (isNarrow) {
                  return Column(children: [SizedBox(height: 200, child: photoSection), const SizedBox(height: 20), identityFields]);
                } else {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 1, child: photoSection),
                      const SizedBox(width: 24),
                      Expanded(flex: 2, child: identityFields),
                    ],
                  );
                }
              }),

              const SizedBox(height: 25),
              _buildSectionLabel('Social Handles'),
              TextField(controller: xHandleController, decoration: dec.copyWith(hintText: "X (Twitter) @handle")),
              const SizedBox(height: 10),
              TextField(controller: instagramHandleController, decoration: dec.copyWith(hintText: "Instagram @handle")),
              const SizedBox(height: 10),
              TextField(controller: githubHandleController, decoration: dec.copyWith(hintText: "GitHub username")),

              const SizedBox(height: 25),
              _buildSectionLabel('Private Contact Info'),
              Row(children: [
                Expanded(child: TextField(controller: firstNameController, decoration: dec.copyWith(hintText: "First Name"))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: lastNameController, decoration: dec.copyWith(hintText: "Last Name"))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: emailController, enabled: false, decoration: dec.copyWith(hintText: "Email", fillColor: Colors.grey[100])),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _openAddressSearch,
                child: AbsorbPointer(
                  child: TextField(
                    controller: street1Controller,
                    decoration: dec.copyWith(
                      hintText: "Tap to search address...",
                      prefixIcon: const Icon(Icons.location_on_outlined, color: Colors.indigo),
                      filled: true,
                      fillColor: Colors.indigo.withValues(alpha: 0.05),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: street2Controller, decoration: dec.copyWith(hintText: "Apt / Suite / Other")),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(flex: 2, child: TextField(controller: cityController, decoration: dec.copyWith(hintText: "City"))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: stateController, decoration: dec.copyWith(hintText: "State"))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: zipController, decoration: dec.copyWith(hintText: "Zip"))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: countryController, decoration: dec.copyWith(hintText: "Country")),

              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isSaving ? null : saveProfile,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, padding: const EdgeInsets.all(20), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                child: Text(_isSaving ? "Saving..." : "Update All Systems"),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String l) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 16), child: Text(l.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.black54)));
}

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

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty) {
      setState(() { _predictions = []; _isSearching = false; });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      try {
        final response = await widget.places.findAutocompletePredictions(query);
        if (mounted) setState(() { _predictions = response.predictions; _isSearching = false; });
      } catch (e) {
        if (mounted) setState(() => _isSearching = false);
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
              decoration: const InputDecoration(hintText: "Start typing address...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 10),
            if (_isSearching) const Center(child: CircularProgressIndicator()),
            Expanded(
              child: ListView.separated(
                itemCount: _predictions.length + 1,
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == _predictions.length) {
                    return ListTile(
                      leading: const Icon(Icons.edit_note),
                      title: Text('Use "${_controller.text}"'),
                      onTap: () => Navigator.pop(context, _controller.text),
                    );
                  }
                  final item = _predictions[index];
                  return ListTile(
                    title: Text(item.primaryText),
                    subtitle: Text(item.secondaryText),
                    leading: const Icon(Icons.location_on),
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void displayMessageToUser(String m, BuildContext c) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}