import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _loginZineController = TextEditingController();
  final _registerZineController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading settings: ${e.toString()}')),
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _firestore.collection('app_settings').doc('main_settings').set({
        'login_zine_shortcode': _loginZineController.text,
        'register_zine_shortcode': _registerZineController.text,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _loginZineController.dispose();
    _registerZineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Login Zine ShortCode:'),
            TextField(
              controller: _loginZineController,
              decoration: const InputDecoration(
                hintText: 'Enter shortcode for login zine',
              ),
            ),
            const SizedBox(height: 20),
            const Text('Register Zine ShortCode:'),
            TextField(
              controller: _registerZineController,
              decoration: const InputDecoration(
                hintText: 'Enter shortcode for register zine',
              ),
            ),
            const SizedBox(height: 40),
            Center(
              child: ElevatedButton(
                onPressed: _saveSettings,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
