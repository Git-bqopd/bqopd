import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NewFanzineModal extends StatefulWidget {
  final String userId; // While editorId will be current user's UID, good to pass for consistency or future use

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
      final String editorId = currentUser.uid; // Use current user's UID as editorId

      await FirebaseFirestore.instance.collection('fanzines').add({
        'title': title,
        'editorId': editorId,
        'creationDate': FieldValue.serverTimestamp(),
        // publicationDate and pages will be added later
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fanzine created successfully!')),
        );
        Navigator.of(context).pop(true); // Pop with a success indicator
      }
    } catch (e) {
      print("Error creating fanzine: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating fanzine: ${e.toString()}')),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_isLoading) ...[
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Fanzine Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a title for the fanzine';
                    }
                    return null;
                  },
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
            onPressed: () {
              Navigator.of(context).pop();
            },
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
