import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_bootstrap.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
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
    try {
      final doc = await _firestore.collection('app_settings').doc('main_settings').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _loginZineController.text = data['login_zine_shortcode'] ?? '';
        _registerZineController.text = data['register_zine_shortcode'] ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _firestore.collection('app_settings').doc('main_settings').set({
        'login_zine_shortcode': _loginZineController.text,
        'register_zine_shortcode': _registerZineController.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _handleCreateProfile() async {
    if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a First and Last Name')),
      );
      return;
    }

    setState(() { _isCreatingProfile = true; });
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Managed Profile Created!')),
        );
      }
    } catch (e) {
      print("Managed Profile Creation Error: $e"); // Debug print
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _isCreatingProfile = false; });
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
              const Text("Create a profile for a historical figure or estate that you will manage."),
              const SizedBox(height: 16),
              TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: "First Name", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: "Last Name", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bioController,
                decoration: const InputDecoration(labelText: "Bio (Optional)", border: OutlineInputBorder()),
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
    final currentUser = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SECTION 1: SHORTCODES ---
              _buildSectionHeader('Shortcodes'),
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('Save Shortcodes'),
                ),
              ),

              const Divider(height: 40, thickness: 2),

              // --- SECTION 2: MANAGED PROFILES ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader('Managed Profiles'),
                  ElevatedButton.icon(
                    onPressed: _showCreateProfileDialog,
                    icon: const Icon(Icons.add),
                    label: const Text("New Profile"),
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
                  stream: _firestore.collection('Users')
                      .where('isManaged', isEqualTo: true)
                      .where('managers', arrayContains: currentUser.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return Text('Error: ${snapshot.error}');
                    if (snapshot.connectionState == ConnectionState.waiting) return const CircularProgressIndicator();

                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text("You don't manage any profiles yet."),
                        ),
                      );
                    }

                    // 2-Column Grid
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 2.5, // Wide cards
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final name = "${data['firstName']} ${data['lastName']}";
                        final managers = List<String>.from(data['managers'] ?? []);
                        final username = data['username'] ?? 'No handle';

                        return Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  "@$username",
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                ),
                                const Spacer(),
                                Text(
                                  "Managers: ${managers.length}",
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).primaryColor,
      ),
    );
  }
}