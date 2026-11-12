import 'dart:async';
import 'package:bqopd_core/bqopd_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/username_service.dart';
import '../utils/script_loader.dart';

class EditInfoWidget extends StatefulWidget {
  final String? targetUserId;
  const EditInfoWidget({super.key, this.targetUserId});

  @override
  State<EditInfoWidget> createState() => _EditInfoWidgetState();
}

class _EditInfoWidgetState extends State<EditInfoWidget> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
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

  String _profileType = 'person';
  bool _isOpenToPublic = false;
  final Map<String, bool> _dayOpen = {
    for (final day in kBusinessDaysOfWeek) day: false,
  };
  final Map<String, TextEditingController> _dayOpenControllers = {
    for (final day in kBusinessDaysOfWeek) day: TextEditingController(),
  };
  final Map<String, TextEditingController> _dayCloseControllers = {
    for (final day in kBusinessDaysOfWeek) day: TextEditingController(),
  };

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
    for (final c in _dayOpenControllers.values) {
      c.dispose();
    }
    for (final c in _dayCloseControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateDefaultUsername() {
    if (_isUsernameManuallyEdited) {
      return;
    }
    final name = firstNameController.text.trim();
    final state = stateController.text.trim();
    if (name.isNotEmpty && state.isNotEmpty) {
      String generated = "$name-from-$state"
          .toLowerCase()
          .replaceAll(' ', '-')
          // ignore: deprecated_member_use
          .replaceAll(RegExp(r'[^a-z0-9-]'), '');
      setState(() => userNameController.text = generated);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }
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
          _profileType = (data['profileType']?.toString() == 'business' ||
                  data['isBusiness'] == true)
              ? 'business'
              : 'person';
          _isOpenToPublic = data['isOpenToPublic'] == true;
          final parsedHours = parseBusinessHours(data['businessHours']);
          for (final day in kBusinessDaysOfWeek) {
            final dh = parsedHours[day] ?? const BusinessDayHours();
            _dayOpen[day] = dh.isOpen;
            _dayOpenControllers[day]!.text = dh.open;
            _dayCloseControllers[day]!.text = dh.close;
          }
          if (_initialUsername.isNotEmpty) {
            _isUsernameManuallyEdited = true;
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error loading profile")),
          );
        }
      }
    }
    if (mounted) {
      setState(() => _isLoadingData = false);
    }
  }

  Map<String, Map<String, dynamic>> _collectBusinessHours() {
    final map = <String, BusinessDayHours>{};
    for (final day in kBusinessDaysOfWeek) {
      map[day] = BusinessDayHours(
        isOpen: _dayOpen[day] ?? false,
        open: _dayOpenControllers[day]?.text ?? '',
        close: _dayCloseControllers[day]?.text ?? '',
      );
    }
    return serializeBusinessHours(map);
  }

  Future<void> saveProfile() async {
    if (_isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (_editingUid.isNotEmpty) {
        final db = FirebaseFirestore.instance;
        final finalUsername = normalizeHandle(userNameController.text);
        final batch = db.batch();
        final bool isBusiness = _profileType == 'business';
        final bool effectiveOpenToPublic = isBusiness && _isOpenToPublic;
        final publicData = {
          'username': finalUsername,
          'displayName': displayNameController.text.trim(),
          'bio': bioController.text.trim(),
          'photoUrl': _profilePhotoUrl,
          'profileType': _profileType,
          'isBusiness': isBusiness,
          'isOpenToPublic': effectiveOpenToPublic,
          'businessHours': _collectBusinessHours(),
          'xHandle': xHandleController.text.trim().replaceAll('@', ''),
          'instagramHandle': instagramHandleController.text.trim().replaceAll('@', ''),
          'githubHandle': githubHandleController.text.trim().replaceAll('@', ''),
          'updatedAt': FieldValue.serverTimestamp(),
          'uid': _editingUid,
        };
        batch.set(
          db.collection('profiles').doc(_editingUid),
          publicData,
          SetOptions(merge: true),
        );
        final privateData = {
          'firstName': firstNameController.text.trim(),
          'lastName': lastNameController.text.trim(),
          'street1': street1Controller.text.trim(),
          'street2': street2Controller.text.trim(),
          'city': cityController.text.trim(),
          'state': stateController.text.trim(),
          'zipCode': zipController.text.trim(),
          'country': countryController.text.trim(),
          'profileType': _profileType,
          'isBusiness': isBusiness,
          'isOpenToPublic': effectiveOpenToPublic,
          'updatedAt': FieldValue.serverTimestamp(),
          'uid': _editingUid,
        };
        batch.set(
          db.collection('Users').doc(_editingUid),
          privateData,
          SetOptions(merge: true),
        );
        await batch.commit();
        if (finalUsername.isNotEmpty && finalUsername != _initialUsername) {
          await claimHandle(finalUsername);
        }
        _initialUsername = finalUsername;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile Saved!")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildBusinessSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'BUSINESS ACCESS & HOURS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Open to the public',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            value: _isOpenToPublic,
            onChanged: (val) {
              setState(() {
                _isOpenToPublic = val ?? false;
              });
            },
          ),
          if (_isOpenToPublic) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'DAY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'OPEN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'CLOSE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final day in kBusinessDaysOfWeek) _buildFlutterDayRow(day),
          ],
        ],
      ),
    );
  }

  Widget _buildFlutterDayRow(String day) {
    final bool isOpen = _dayOpen[day] ?? false;
    final String label = kBusinessDayLabels[day] ?? day;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: InkWell(
              onTap: () {
                setState(() {
                  final next = !isOpen;
                  _dayOpen[day] = next;
                  if (!next) {
                    _dayOpenControllers[day]?.clear();
                    _dayCloseControllers[day]?.clear();
                  }
                });
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isOpen,
                      onChanged: (val) {
                        setState(() {
                          final next = val ?? false;
                          _dayOpen[day] = next;
                          if (!next) {
                            _dayOpenControllers[day]?.clear();
                            _dayCloseControllers[day]?.clear();
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isOpen ? FontWeight.w600 : FontWeight.normal,
                        color: isOpen ? Colors.black87 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: TextField(
              controller: _dayOpenControllers[day],
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                hintText: isOpen ? '9:00 AM' : 'Closed',
                filled: true,
                fillColor: isOpen ? Colors.white : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onChanged: (val) {
                if (val.trim().isNotEmpty && !isOpen) {
                  setState(() => _dayOpen[day] = true);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: TextField(
              controller: _dayCloseControllers[day],
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                hintText: isOpen ? '5:00 PM' : 'Closed',
                filled: true,
                fillColor: isOpen ? Colors.white : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onChanged: (val) {
                if (val.trim().isNotEmpty && !isOpen) {
                  setState(() => _dayOpen[day] = true);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    const Text(
                      'Profile Editor',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'person',
                            label: Text('person'),
                          ),
                          ButtonSegment<String>(
                            value: 'business',
                            label: Text('business'),
                          ),
                        ],
                        selected: {_profileType},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            setState(() {
                              _profileType = selection.first;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: displayNameController,
                      decoration: InputDecoration(
                        labelText: _profileType == 'business'
                            ? "Business / Display Name"
                            : "Display Name",
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: userNameController,
                      decoration: const InputDecoration(
                        labelText: "Username",
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bioController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Bio",
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    if (_profileType == 'business') ...[
                      const SizedBox(height: 14),
                      _buildBusinessSection(),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isSaving ? null : saveProfile,
                      child: Text(_isSaving ? "Saving..." : "Save Profile"),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}