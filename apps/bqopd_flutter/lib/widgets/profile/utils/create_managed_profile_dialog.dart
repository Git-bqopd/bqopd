import 'package:flutter/material.dart';
import 'package:bqopd_core/bqopd_core.dart';

class CreateManagedProfileDialog extends StatefulWidget {
  const CreateManagedProfileDialog({super.key});

  @override
  State<CreateManagedProfileDialog> createState() => _CreateManagedProfileDialogState();
}

class _CreateManagedProfileDialogState extends State<CreateManagedProfileDialog> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateManagedProfile() async {
    if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a First and Last Name')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      await createManagedProfile(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        bio: _bioController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Managed Profile Created!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating profile: $e')),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Create Managed Profile"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Create a profile for a historical figure or estate that you will manage."),
            const SizedBox(height: 16),
            TextField(controller: _firstNameController, decoration: const InputDecoration(labelText: "First Name", border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _lastNameController, decoration: const InputDecoration(labelText: "Last Name", border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _bioController, decoration: const InputDecoration(labelText: "Bio (Optional)", border: OutlineInputBorder()), maxLines: 2),
            if (_isCreating)
              const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: LinearProgressIndicator(),
              )
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _isCreating ? null : () => Navigator.pop(context),
            child: const Text("Cancel")
        ),
        ElevatedButton(
            onPressed: _isCreating ? null : _handleCreateManagedProfile,
            child: const Text("Create")
        ),
      ],
    );
  }
}