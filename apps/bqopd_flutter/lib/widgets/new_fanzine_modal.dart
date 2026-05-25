import 'package:bqopd_core/bqopd_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/shortcode_service.dart';

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

  // Checkbox state for layout preference
  bool _twoPageView = false;

  bool _isVanityEligible(User? user) {
    if (user == null || user.email == null) return false;
    // Inlined check for vanity eligibility to bypass analyzer linking delays
    return user.email!.trim().toLowerCase() == 'kevin@712liberty.com';
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Not logged in.')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String title = _titleController.text;
      final String editorId = currentUser.uid;
      final bool useVanity = _isVanityEligible(currentUser);

      final newFanzineRef =
      FirebaseFirestore.instance.collection('fanzines').doc();

      // Use the newly created Service
      final ShortcodeService shortcodeService = ShortcodeService();
      final String? shortCode = await shortcodeService.assignShortcode(
        contentType: 'fanzine',
        contentId: newFanzineRef.id,
        isVanity: useVanity,
      );

      if (shortCode != null) {
        await newFanzineRef.set({
          'title': title,
          'editorId': editorId,
          'ownerId': editorId,
          'isLive': false,
          'processingStatus': 'idle',
          'creationDate': FieldValue.serverTimestamp(),
          'shortCode': shortCode,
          'shortCodeKey': shortCode.toUpperCase(),
          'twoPage': _twoPageView,
          'mentionedUsers': [],
          'draftEntities': [],
          'isSoftPublished': false,
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
      debugPrint("Error creating fanzine: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
                const SizedBox(height: 16),
                // Checkbox Row
                Row(
                  children: [
                    Checkbox(
                      value: _twoPageView,
                      onChanged: (val) =>
                          setState(() => _twoPageView = val ?? false),
                    ),
                    const Flexible(
                      child: Text(
                          "Enable Two-Page Grid View?\n(Default is Single Column Scroll)"),
                    ),
                  ],
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