import 'dart:async';

import 'package:bqopd_core/bqopd_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import '../services/username_service.dart';
import '../env.dart';
import '../utils/script_loader.dart';

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
    displayNameController.dispose(); userNameController.dispose(); emailController.dispose();
    bioController.dispose(); street1Controller.dispose(); street2Controller.dispose();
    cityController.dispose(); stateController.dispose(); zipController.dispose();
    countryController.dispose(); firstNameController.dispose(); lastNameController.dispose();
    xHandleController.dispose(); instagramHandleController.dispose(); githubHandleController.dispose();
    super.dispose();
  }

  void _updateDefaultUsername() {
    if (_isUsernameManuallyEdited) return;
    final name = firstNameController.text.trim();
    final state = stateController.text.trim();
    if (name.isNotEmpty && state.isNotEmpty) {
      String generated = "$name-from-$state".toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
      setState(() => userNameController.text = generated);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoadingData = true);
    if (_editingUid.isNotEmpty) {
      try {
        final db = FirebaseFirestore.instance;
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error loading profile")));
      }
    }
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> saveProfile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      if (_editingUid.isNotEmpty) {
        final db = FirebaseFirestore.instance;
        final finalUsername = normalizeHandle(userNameController.text);
        final batch = db.batch();
        final publicData = {'username': finalUsername, 'displayName': displayNameController.text.trim(), 'bio': bioController.text.trim(), 'photoUrl': _profilePhotoUrl, 'xHandle': xHandleController.text.trim().replaceAll('@', ''), 'instagramHandle': instagramHandleController.text.trim().replaceAll('@', ''), 'githubHandle': githubHandleController.text.trim().replaceAll('@', ''), 'updatedAt': FieldValue.serverTimestamp(), 'uid': _editingUid};
        batch.set(db.collection('profiles').doc(_editingUid), publicData, SetOptions(merge: true));
        final privateData = {'firstName': firstNameController.text.trim(), 'lastName': lastNameController.text.trim(), 'street1': street1Controller.text.trim(), 'street2': street2Controller.text.trim(), 'city': cityController.text.trim(), 'state': stateController.text.trim(), 'zipCode': zipController.text.trim(), 'country': countryController.text.trim(), 'updatedAt': FieldValue.serverTimestamp(), 'uid': _editingUid};
        batch.set(db.collection('Users').doc(_editingUid), privateData, SetOptions(merge: true));
        await batch.commit();
        if (finalUsername.isNotEmpty && finalUsername != _initialUsername) await claimHandle(finalUsername);
        _initialUsername = finalUsername;
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Saved!")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF1B255)),
      child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: _isLoadingData ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Profile Editor', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(controller: displayNameController, decoration: const InputDecoration(labelText: "Display Name", filled: true, fillColor: Colors.white)),
            const SizedBox(height: 10),
            TextField(controller: userNameController, decoration: const InputDecoration(labelText: "Username", filled: true, fillColor: Colors.white)),
            const SizedBox(height: 10),
            TextField(controller: bioController, maxLines: 3, decoration: const InputDecoration(labelText: "Bio", filled: true, fillColor: Colors.white)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _isSaving ? null : saveProfile, child: Text(_isSaving ? "Saving..." : "Save Profile"))
          ]))
      ),
    );
  }
}