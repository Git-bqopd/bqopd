import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_bootstrap.dart';
import '../widgets/reader_panels/social_matrix_tab.dart'; // NEW

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _loginZineController = TextEditingController();
  final _registerZineController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _bioController = TextEditingController();

  bool _isCreatingProfile = false;
  int _activeSubTab = 0; // 0: Shortcodes, 1: Managed Profiles, 2: Permissions, 3: Social Buttons

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _loginZineController.dispose();
    _registerZineController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await _firestore
          .collection('app_settings')
          .doc('main_settings')
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _loginZineController.text = data['login_zine_shortcode'] ?? '';
        _registerZineController.text = data['register_zine_shortcode'] ?? '';
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error loading settings: ${e.toString()}')),
      );
    }
  }

  Future<void> _saveSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _firestore.collection('app_settings').doc('main_settings').set({
        'login_zine_shortcode': _loginZineController.text,
        'register_zine_shortcode': _registerZineController.text,
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error saving settings: ${e.toString()}')),
      );
    }
  }

  Future<void> _handleCreateProfile() async {
    if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a First and Last Name')),
      );
      return;
    }

    setState(() {
      _isCreatingProfile = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    try {
      await createManagedProfile(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        bio: _bioController.text,
      );

      _firstNameController.clear();
      _lastNameController.clear();
      _bioController.clear();

      messenger.showSnackBar(
        const SnackBar(content: Text('Managed Profile Created!')),
      );
    } catch (e) {
      debugPrint("Managed Profile Creation Error: $e");
      messenger.showSnackBar(
        SnackBar(content: Text('Error creating profile: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
        });
      }
    }
  }

  void _showCreateProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create Managed Profile"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  "Create a profile for a historical figure or estate that you will manage."),
              const SizedBox(height: 16),
              TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                    labelText: "First Name", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                    labelText: "Last Name", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bioController,
                decoration: const InputDecoration(
                    labelText: "Bio (Optional)", border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: _handleCreateProfile,
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Column(
        children: [
          // Sub-navigation bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSubNavButton("shortcodes", 0),
                  _buildSubNavButton("managed profiles", 1),
                  _buildSubNavButton("permissions", 2),
                  _buildSubNavButton("social buttons", 3), // NEW
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _buildActiveTabContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubNavButton(String label, int index) {
    final bool isActive = _activeSubTab == index;
    return TextButton(
      onPressed: () => setState(() => _activeSubTab = index),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? Colors.indigo : Colors.grey,
          decoration: isActive ? TextDecoration.underline : null,
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeSubTab) {
      case 0:
        return _buildShortcodesSection();
      case 1:
        return _buildManagedProfilesSection();
      case 2:
        return _buildPermissionsSection();
      case 3:
        return const SocialMatrixTab(); // NEW
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildShortcodesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Global Shortcodes'),
        const SizedBox(height: 10),
        const Text(
          "Set the default zines that appear during the login and registration flows.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _loginZineController,
          decoration: const InputDecoration(
            labelText: 'Login Zine ShortCode',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _registerZineController,
          decoration: const InputDecoration(
            labelText: 'Register Zine ShortCode',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _saveSettings,
            child: const Text('Save Shortcodes'),
          ),
        ),
      ],
    );
  }

  Widget _buildManagedProfilesSection() {
    final currentUser = _auth.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Managed Profiles'),
            ElevatedButton.icon(
              onPressed: _showCreateProfileDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text("New Profile", style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isCreatingProfile)
          const Padding(
            padding: EdgeInsets.only(bottom: 20.0),
            child: LinearProgressIndicator(),
          ),
        if (currentUser != null)
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('profiles')
                .where('isManaged', isEqualTo: true)
                .where('managers', arrayContains: currentUser.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('Error: ${snapshot.error}');
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(child: Text("You don't manage any profiles yet.", style: TextStyle(color: Colors.grey))),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final name = data['displayName'] ?? "Untitled";
                  final username = data['username'] ?? 'No handle';

                  return Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text("@$username", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                          const Spacer(),
                          Text("Managed by you", style: TextStyle(fontSize: 10, color: Colors.indigo[300])),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildPermissionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('User Permissions'),
        const Text(
          "Manage global access levels for registered users. Changes take effect immediately.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('Users').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Error: ${snapshot.error}');
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final users = snapshot.data?.docs ?? [];

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: users.length,
              separatorBuilder: (c, i) => const Divider(),
              itemBuilder: (context, index) {
                final userData = users[index].data() as Map<String, dynamic>;
                final uid = users[index].id;
                final currentRole = userData['role'] ?? 'user';

                return FutureBuilder<DocumentSnapshot>(
                  future: _firestore.collection('profiles').doc(uid).get(),
                  builder: (context, profileSnap) {
                    final pData = profileSnap.data?.data() as Map?;
                    final String username = pData?['username'] ?? 'unknown';
                    final String displayName = pData?['displayName'] ?? '';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(displayName.isNotEmpty ? displayName : "@$username", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text("UID: $uid", style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
                      trailing: DropdownButtonHideUnderline(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: DropdownButton<String>(
                            value: ['admin', 'moderator', 'curator', 'user'].contains(currentRole) ? currentRole : 'user',
                            style: const TextStyle(fontSize: 12, color: Colors.black),
                            items: const [
                              DropdownMenuItem(value: 'admin', child: Text("Admin")),
                              DropdownMenuItem(value: 'moderator', child: Text("Moderator")),
                              DropdownMenuItem(value: 'curator', child: Text("Curator")),
                              DropdownMenuItem(value: 'user', child: Text("Standard User")),
                            ],
                            onChanged: (newRole) async {
                              if (newRole == null) return;
                              final messenger = ScaffoldMessenger.of(context);

                              try {
                                await _firestore.collection('Users').doc(uid).update({
                                  'role': newRole,
                                  'isCurator': newRole == 'curator' || newRole == 'admin' || newRole == 'moderator',
                                });

                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Permission updated!')),
                                );
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Permission update failed: $e')),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).primaryColor,
      ),
    );
  }
}