import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../services/user_bootstrap.dart';
import '../../../services/username_service.dart';

class ProfileEntityRow extends StatelessWidget {
  final String name;
  final int count;

  const ProfileEntityRow({
    super.key,
    required this.name,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final handle = normalizeHandle(name);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usernames').doc(handle).snapshots(),
      builder: (context, snapshot) {
        Widget statusWidget;

        if (!snapshot.hasData) {
          statusWidget = const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        } else if (snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String linkText = '/$handle';
          if (data['isAlias'] == true) {
            linkText = '/$handle -> /${data['redirect'] ?? 'unknown'}';
          }
          statusWidget = InkWell(
            onTap: () => context.go('/$handle'),
            child: Text(
              linkText,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                decoration: TextDecoration.underline,
              ),
            ),
          );
        } else {
          statusWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _createProfile(context, name),
                child: const Text("Create", style: TextStyle(color: Colors.green, fontSize: 11)),
              ),
              TextButton(
                onPressed: () => _createAlias(context, name),
                child: const Text("Alias", style: TextStyle(color: Colors.orange, fontSize: 11)),
              ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  "$count",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),
              Expanded(
                child: Text(name, style: const TextStyle(fontSize: 13)),
              ),
              statusWidget,
            ],
          ),
        );
      },
    );
  }

  Future<void> _createProfile(BuildContext context, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    String first = name;
    String last = "";

    if (name.contains(' ')) {
      final parts = name.split(' ');
      first = parts.first;
      last = parts.sublist(1).join(' ');
    }

    final expectedHandle = normalizeHandle(name);

    try {
      await createManagedProfile(
        firstName: first,
        lastName: last,
        bio: "Auto-created from Editor Widget",
        explicitHandle: expectedHandle,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final target = await showDialog<String>(
      context: context,
      builder: (c) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text("Create Alias for '$name'"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter EXISTING username (target):"),
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: "e.g. julius-schwartz"),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
            TextButton(
              onPressed: () => Navigator.pop(c, controller.text.trim()),
              child: const Text("Create Alias"),
            ),
          ],
        );
      },
    );

    if (target == null || target.isEmpty) return;

    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}