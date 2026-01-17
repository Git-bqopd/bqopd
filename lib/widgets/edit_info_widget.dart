import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // kIsWeb, defaultTargetPlatform
import 'package:flutter/material.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:go_router/go_router.dart';
import '../services/username_service.dart';
import '../env.dart'; // Import Env
import 'image_selector_modal.dart'; // Import the new selector

class EditInfoWidget extends StatefulWidget {
  final String? targetUserId; // Optional: If null, edits current user

  const EditInfoWidget({super.key, this.targetUserId});

  @override
  State<EditInfoWidget> createState() => _EditInfoWidgetState();
}

class _EditInfoWidgetState extends State<EditInfoWidget> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  late final FlutterGooglePlacesSdk _places;

  final TextEditingController displayNameController = TextEditingController(); // NEW
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

  // Socials Controllers
  final TextEditingController xHandleController = TextEditingController();
  final TextEditingController instagramHandleController =
  TextEditingController();

  String? _profilePhotoUrl; // State for the photo URL

  bool _isLoadingData = true;
  bool _isSaving = false;
  String _initialUsername = "";
  bool _isUsernameManuallyEdited = false;

  // Computed property to get the ID we are actually editing
  String get _editingUid => widget.targetUserId ?? currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();

    // LOGIC TO SELECT THE CORRECT API KEY
    String apiKey = '';

    if (kIsWeb) {
      apiKey = Env.googleApiKeyWeb;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      apiKey = Env.googleApiKeyAndroid;
    }

    _places = FlutterGooglePlacesSdk(apiKey);

    _loadUserData();

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
    super.dispose();
  }

  void _updateDefaultUsername() {
    if (_isUsernameManuallyEdited) return;

    final name = firstNameController.text.trim();
    final state = stateController.text.trim();

    if (name.isNotEmpty && state.isNotEmpty) {
      String generated = "$name-from-$state";
      generated = generated
          .toLowerCase()
          .replaceAll(' ', '-')
          .replaceAll(RegExp(r'[^a-z0-9-]'), '');

      setState(() {
        userNameController.text = generated;
      });
    }
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
        if (types.contains('street_number')) streetNum = c.name;
        if (types.contains('route')) route = c.name;
        if (types.contains('locality') || types.contains('postal_town')) {
          city = c.name;
        }
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
      setState(() => _isLoadingData = false);
    }
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingData = true;
    });

    if (_editingUid.isNotEmpty) {
      try {
        // If editing self, prefer Auth email. If other, placeholder.
        if (widget.targetUserId == null && currentUser != null) {
          emailController.text = currentUser!.email ?? 'No Email Found';
        } else {
          emailController.text = 'Managed Account (No Email)';
        }

        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(_editingUid)
            .get();

        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _initialUsername = data['username'] ?? '';
            userNameController.text = _initialUsername;
            if (_initialUsername.isNotEmpty) {
              _isUsernameManuallyEdited = true;
            }

            displayNameController.text = data['displayName'] ?? ''; // Load Display Name
            bioController.text = data['bio'] ?? '';
            street1Controller.text = data['street1'] ?? '';
            street2Controller.text = data['street2'] ?? '';
            cityController.text = data['city'] ?? '';
            stateController.text = data['state'] ?? '';
            zipController.text = data['zipCode'] ?? '';
            countryController.text = data['country'] ?? '';
            firstNameController.text = data['firstName'] ?? '';
            lastNameController.text = data['lastName'] ?? '';

            xHandleController.text = data['xHandle'] ?? '';
            instagramHandleController.text = data['instagramHandle'] ?? '';
            _profilePhotoUrl = data['photoUrl'];

            // If Managed user has a stored email field (rare), show it
            if (widget.targetUserId != null &&
                data.containsKey('email') &&
                data['email'] != '') {
              emailController.text = data['email'];
            }
          });
        }
      } catch (e) {
        if (mounted) displayMessageToUser("Error loading profile", context);
      } finally {
        if (mounted) {
          setState(() {
            _isLoadingData = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  Future<void> saveProfile() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });

    try {
      if (_editingUid.isNotEmpty) {
        final finalUsername = normalizeHandle(userNameController.text);

        final Map<String, dynamic> dataToUpdate = {
          'username': finalUsername,
          'displayName': displayNameController.text.trim(), // Save Display Name
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
          'photoUrl': _profilePhotoUrl,

          // Socials
          'xHandle': xHandleController.text.trim().replaceAll('@', ''),
          'instagramHandle':
          instagramHandleController.text.trim().replaceAll('@', ''),

          // Only update email if we are editing ourselves
          if (widget.targetUserId == null && currentUser != null)
            'email': currentUser!.email,

          'uid': _editingUid,
        };

        await FirebaseFirestore.instance
            .collection('Users')
            .doc(_editingUid)
            .set(dataToUpdate, SetOptions(merge: true));

        // Claim handle if it changed
        if (finalUsername.isNotEmpty && finalUsername != _initialUsername) {
          if (widget.targetUserId != null) {
            final db = FirebaseFirestore.instance;
            final shortCodeKey = finalUsername.toUpperCase();
            final short =
            await db.collection('shortcodes').doc(shortCodeKey).get();
            if (!short.exists) {
              final batch = db.batch();
              batch.set(db.collection('usernames').doc(finalUsername), {
                'uid': _editingUid,
                'isManaged': true,
                'createdAt': FieldValue.serverTimestamp(),
              });
              batch.set(db.collection('shortcodes').doc(shortCodeKey), {
                'type': 'user',
                'contentId': _editingUid,
                'createdAt': FieldValue.serverTimestamp(),
              });
              await batch.commit();
            }
          } else {
            await claimHandle(finalUsername);
          }
        }

        _initialUsername = finalUsername;
        userNameController.text = finalUsername;

        if (mounted) displayMessageToUser("Profile Saved!", context);
      }
    } catch (e) {
      if (mounted) displayMessageToUser("Error saving: $e", context);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _onChangePhoto() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => ImageSelectorModal(userId: _editingUid),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _profilePhotoUrl = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration defaultDecoration = InputDecoration(
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.zero,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Theme.of(context).primaryColor),
        borderRadius: BorderRadius.zero,
      ),
      fillColor: Colors.white,
      filled: true,
      contentPadding: const EdgeInsets.all(15),
      hintStyle: TextStyle(color: Colors.grey[500]),
      isDense: true,
    );

    final ButtonStyle actionButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.black87,
      backgroundColor: Colors.white.withValues(alpha: 0.3),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    );

    final String pageTitle = widget.targetUserId != null
        ? 'Edit Managed Profile'
        : 'Edit Your Profile';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF1B255),
      ),
      child: ClipRect(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: _isLoadingData
              ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()))
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(pageTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColorDark)),
              const SizedBox(height: 20),

              // --- SPLIT LAYOUT START ---
              LayoutBuilder(
                builder: (context, constraints) {
                  // Use a column on very narrow screens, otherwise row
                  bool isNarrow = constraints.maxWidth < 500;

                  Widget photoSection = GestureDetector(
                    onTap: _onChangePhoto,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: 5 / 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              border:
                              Border.all(color: Colors.grey[400]!),
                            ),
                            child: _profilePhotoUrl != null &&
                                _profilePhotoUrl!.isNotEmpty
                                ? Image.network(
                              _profilePhotoUrl!,
                              fit: BoxFit
                                  .cover, // Or contain based on preference
                              errorBuilder: (c, e, s) => const Icon(
                                  Icons.broken_image,
                                  size: 40),
                            )
                                : const Icon(Icons.person,
                                size: 60, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "click to change photo",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  );

                  Widget fieldsSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionLabel('Public Information'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: displayNameController,
                        decoration: defaultDecoration.copyWith(
                            hintText: "Display Name (Public)"),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: userNameController,
                        decoration: defaultDecoration.copyWith(
                            hintText: "Username (e.g. kevin-from-wi)"),
                        onChanged: (val) =>
                        _isUsernameManuallyEdited = true,
                      ),
                      if (!_isUsernameManuallyEdited &&
                          firstNameController.text.isNotEmpty &&
                          stateController.text.isNotEmpty)
                        Padding(
                          padding:
                          const EdgeInsets.only(top: 4.0, left: 4.0),
                          child: Text("Auto-generating handle...",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.indigo.shade800,
                                  fontStyle: FontStyle.italic)),
                        ),
                      const SizedBox(height: 10),
                      TextField(
                          controller: bioController,
                          maxLines: 3,
                          decoration: defaultDecoration.copyWith(
                              hintText: "Bio (tell us about yourself!)"),
                          keyboardType: TextInputType.multiline),
                      const SizedBox(height: 10),
                      TextField(
                          controller: xHandleController,
                          decoration: defaultDecoration.copyWith(
                              hintText: "X (Twitter) Username")),
                      const SizedBox(height: 10),
                      TextField(
                          controller: instagramHandleController,
                          decoration: defaultDecoration.copyWith(
                              hintText: "Instagram Username")),
                    ],
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        SizedBox(height: 200, child: photoSection),
                        const SizedBox(height: 20),
                        fieldsSection,
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Photo (Flex 1)
                        Expanded(flex: 1, child: photoSection),
                        const SizedBox(width: 20),
                        // Right: Fields (Flex 2)
                        Expanded(flex: 2, child: fieldsSection),
                      ],
                    );
                  }
                },
              ),
              // --- SPLIT LAYOUT END ---

              const SizedBox(height: 25),

              // Rest of the form (Full Width)
              _buildSectionLabel('Private Information'),
              const SizedBox(height: 10),
              TextField(
                  controller: emailController,
                  enabled: false,
                  decoration: defaultDecoration.copyWith(
                      hintText: "email", fillColor: Colors.grey[200]),
                  style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: firstNameController,
                          decoration: defaultDecoration.copyWith(
                              hintText: "First Name"),
                          textCapitalization: TextCapitalization.words)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: lastNameController,
                          decoration: defaultDecoration.copyWith(
                              hintText: "Last Name"),
                          textCapitalization: TextCapitalization.words)),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _openAddressSearch,
                child: AbsorbPointer(
                  child: TextField(
                    controller: street1Controller,
                    decoration: defaultDecoration.copyWith(
                      hintText: "Tap to search address...",
                      prefixIcon: const Icon(Icons.location_on_outlined,
                          color: Colors.indigo),
                      filled: true,
                      fillColor: Colors.indigo.withValues(alpha: 0.05),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: street2Controller,
                  decoration: defaultDecoration.copyWith(
                      hintText: "Apt / Suite / Other")),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      flex: 2,
                      child: TextField(
                          controller: cityController,
                          decoration: defaultDecoration.copyWith(
                              hintText: "City"))),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 1,
                      child: TextField(
                          controller: stateController,
                          decoration: defaultDecoration.copyWith(
                              hintText: "State"))),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 1,
                      child: TextField(
                          controller: zipController,
                          decoration: defaultDecoration.copyWith(
                              hintText: "Zip"))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: countryController,
                  decoration:
                  defaultDecoration.copyWith(hintText: "Country")),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : saveProfile,
                      style: actionButtonStyle,
                      child:
                      Text(_isSaving ? "Saving..." : "Save Profile"),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (_initialUsername.isNotEmpty) {
                          context.pushNamed('shortlink',
                              pathParameters: {'code': _initialUsername});
                        } else {
                          context.push('/profile');
                        }
                      },
                      style: actionButtonStyle,
                      child: const Text("View Public Profile"),
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
      child: Text(label,
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColorDark)),
    );
  }
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
  String? _errorMessage;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

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
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  Navigator.pop(context, val.trim());
                }
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
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

    if (_predictions.isEmpty) {
      if (_controller.text.isNotEmpty) {
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
                  child: Text("No Google matches found.",
                      style: TextStyle(color: Colors.grey))),
            ),
          ],
        );
      }
      return const Center(
          child: Text("Start typing to search...",
              style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      itemCount: _predictions.length + 1,
      separatorBuilder: (c, i) => const Divider(height: 1),
      itemBuilder: (context, index) {
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
          subtitle: Text(item.secondaryText),
          leading: const Icon(Icons.location_on, color: Colors.grey),
          onTap: () => Navigator.pop(context, item),
        );
      },
    );
  }
}

void displayMessageToUser(String message, BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
    ),
  );
}