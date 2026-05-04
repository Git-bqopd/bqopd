import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';

import '../blocs/edit_info/edit_info_bloc.dart';
import '../services/location_service.dart';
import 'image_selector_modal.dart';

/// Managed profile and personal info editor.
/// BLoC architecture implemented. UI manages TextFields only.
class EditInfoWidget extends StatefulWidget {
  final String targetUserId;

  const EditInfoWidget({super.key, required this.targetUserId});

  @override
  State<EditInfoWidget> createState() => _EditInfoWidgetState();
}

class _EditInfoWidgetState extends State<EditInfoWidget> {
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
  bool _isUsernameManuallyEdited = false;

  @override
  void initState() {
    super.initState();
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

  void _populateControllers(EditInfoState state) {
    final user = state.userData;
    final profile = state.profileData;

    emailController.text = user['email'] ?? '';
    firstNameController.text = user['firstName'] ?? '';
    lastNameController.text = user['lastName'] ?? '';
    street1Controller.text = user['street1'] ?? '';
    street2Controller.text = user['street2'] ?? '';
    cityController.text = user['city'] ?? '';
    stateController.text = user['state'] ?? '';
    zipController.text = user['zipCode'] ?? '';
    countryController.text = user['country'] ?? '';

    userNameController.text = profile['username'] ?? '';
    displayNameController.text = profile['displayName'] ?? '';
    bioController.text = profile['bio'] ?? '';
    xHandleController.text = profile['xHandle'] ?? '';
    instagramHandleController.text = profile['instagramHandle'] ?? '';
    githubHandleController.text = profile['githubHandle'] ?? '';

    setState(() {
      _profilePhotoUrl = profile['photoUrl'];
      if (state.initialUsername.isNotEmpty) {
        _isUsernameManuallyEdited = true;
      }
    });
  }

  void _populateAddressControllers(Map<String, String> addressData) {
    setState(() {
      street1Controller.text = addressData['street1'] ?? '';
      cityController.text = addressData['city'] ?? '';
      stateController.text = addressData['state'] ?? '';
      zipController.text = addressData['zipCode'] ?? '';
      countryController.text = addressData['country'] ?? '';
    });
  }

  void _openAddressSearch() async {
    final locationService = context.read<LocationService>();
    final dynamic result = await showDialog(
      context: context,
      builder: (context) => _AddressSearchDialog(locationService: locationService),
    );

    if (result is AutocompletePrediction && mounted) {
      if (result.placeId.isNotEmpty) {
        context.read<EditInfoBloc>().add(FetchAddressDetailsRequested(result.placeId));
      }
    } else if (result is String && result.isNotEmpty && mounted) {
      setState(() {
        street1Controller.text = result;
      });
    }
  }

  void _saveProfile(EditInfoState state) {
    context.read<EditInfoBloc>().add(SaveProfileRequested(
      uid: widget.targetUserId,
      displayName: displayNameController.text,
      userName: userNameController.text,
      email: emailController.text,
      bio: bioController.text,
      street1: street1Controller.text,
      street2: street2Controller.text,
      city: cityController.text,
      state: stateController.text,
      zipCode: zipController.text,
      country: countryController.text,
      firstName: firstNameController.text,
      lastName: lastNameController.text,
      xHandle: xHandleController.text,
      instagramHandle: instagramHandleController.text,
      githubHandle: githubHandleController.text,
      profilePhotoUrl: _profilePhotoUrl,
      initialUsername: state.initialUsername,
    ));
  }

  void _onChangePhoto() async {
    final result = await showDialog<String>(
        context: context,
        builder: (context) => ImageSelectorModal(userId: widget.targetUserId)
    );
    if (result != null) setState(() => _profilePhotoUrl = result);
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration dec = InputDecoration(
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black12), borderRadius: BorderRadius.zero),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black, width: 2), borderRadius: BorderRadius.zero),
      fillColor: Colors.white, filled: true, isDense: true, contentPadding: const EdgeInsets.all(15),
    );

    final String pageTitle = 'Edit Profile';

    return BlocConsumer<EditInfoBloc, EditInfoState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (context, state) {
          if (state.status == EditInfoStatus.loaded) {
            _populateControllers(state);
          } else if (state.status == EditInfoStatus.addressLoaded && state.addressData != null) {
            _populateAddressControllers(state.addressData!);
          } else if (state.status == EditInfoStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Saved!")));
          } else if (state.status == EditInfoStatus.failure && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${state.errorMessage}")));
          }
        },
        builder: (context, state) {
          final bool isLoadingData = state.status == EditInfoStatus.initial || state.status == EditInfoStatus.loading;
          final bool isSaving = state.status == EditInfoStatus.saving;
          final bool isAddressLoading = state.status == EditInfoStatus.addressLoading;

          return Container(
            decoration: const BoxDecoration(color: Color(0xFFF1B255)),
            child: Padding(
              padding: const EdgeInsets.all(25.0),
              child: isLoadingData
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
                            hintText: isAddressLoading ? "Loading address..." : "Tap to search address...",
                            prefixIcon: isAddressLoading
                                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                : const Icon(Icons.location_on_outlined, color: Colors.indigo),
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
                      onPressed: isSaving ? null : () => _saveProfile(state),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, padding: const EdgeInsets.all(20), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                      child: Text(isSaving ? "Saving..." : "Update All Systems"),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        }
    );
  }

  Widget _buildSectionLabel(String l) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 16), child: Text(l.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.black54)));
}

class _AddressSearchDialog extends StatefulWidget {
  final LocationService locationService;
  const _AddressSearchDialog({required this.locationService});

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
        final predictions = await widget.locationService.getPredictions(query);
        if (mounted) setState(() { _predictions = predictions; _isSearching = false; });
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