import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/shortcode_generator.dart';

class NewFanzineModal extends StatefulWidget {
  final String userId;

  const NewFanzineModal({
    super.key,
    required this.userId,
  });

  @override
  State<NewFanzineModal> createState() => _NewFanzineModalState();
}

class _NewFanzineModalState extends State<NewFanzineModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  bool _isLoading = false;

  /// Check if this user gets special "bqopd" codes
  bool _isVanityEligible(User? user) {
    if (user == null || user.email == null) return false;

    // Check for your specific email or any "bqopd" email
    return user.email == 'kevin@712liberty.com' ||
        user.email!.contains('bqopd');
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Not logged in. Cannot create fanzine.')),
        );
      }
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final String title = _titleController.text;
      final String editorId = currentUser.uid;
      final bool useVanity = _isVanityEligible(currentUser);

      final newFanzineRef = FirebaseFirestore.instance.collection('fanzines').doc();

      // Pass the isVanity flag to our new generator
      final String? shortCode = await assignShortcode(
        FirebaseFirestore.instance,
        'fanzine',
        newFanzineRef.id,
        isVanity: useVanity,
      );

      if (shortCode != null) {
        await newFanzineRef.set({
          'title': title,
          'editorId': editorId,
          'creationDate': FieldValue.serverTimestamp(),
          'shortCode': shortCode, // Saves "N7bqopd4" (Display version)
          'shortCodeKey': shortCode.toUpperCase(), // Normalized key for searching
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fanzine created! Code: $shortCode')),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('Failed to generate a unique shortcode.');
      }
    } catch (e) {
      print("Error creating fanzine: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Make New Fanzine'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: CircularProgressIndicator(),
                ),
              if (!_isLoading) ...[
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Fanzine Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                  (value == null || value.isEmpty) ? 'Please enter a title' : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (!_isLoading)
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        if (!_isLoading)
          ElevatedButton(
            onPressed: _handleSubmit,
            child: const Text('Save'),
          ),
      ],
    );
  }
}