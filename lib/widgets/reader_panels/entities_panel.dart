import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/user_bootstrap.dart';
import '../../services/username_service.dart';

class EntitiesPanel extends StatelessWidget {
  final String text;

  const EntitiesPanel({super.key, required this.text});

  List<String> _parseEntities(String content) {
    final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
    final matches = regex.allMatches(content);
    final Set<String> results = {};
    for (final m in matches) {
      final name = m.group(1);
      if (name != null && name.isNotEmpty) results.add(name);
    }
    return results.toList();
  }

  @override
  Widget build(BuildContext context) {
    final entities = _parseEntities(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("DETECTED ENTITIES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        if (entities.isEmpty)
          const Text("No entity links found in page text.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entities.length,
            separatorBuilder: (c, i) => const Divider(height: 1),
            itemBuilder: (c, i) => EntityRow(name: entities[i]),
          ),
      ],
    );
  }
}

class EntityRow extends StatelessWidget {
  final String name;
  const EntityRow({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final handle = normalizeHandle(name);
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usernames').doc(handle).snapshots(),
      builder: (context, snapshot) {
        Widget statusWidget;
        if (!snapshot.hasData) {
          statusWidget = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String linkText = '/$handle';
          if (data['isAlias'] == true) linkText = '/$handle -> /${data['redirect'] ?? 'unknown'}';
          statusWidget = Text(linkText, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline));
        } else {
          statusWidget = Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => _createProfile(context, name), child: const Text("Create", style: TextStyle(color: Colors.green, fontSize: 11))),
            TextButton(onPressed: () => _createAlias(context, name), child: const Text("Alias", style: TextStyle(color: Colors.orange, fontSize: 11))),
          ]);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
            statusWidget,
          ]),
        );
      },
    );
  }

  Future<void> _createProfile(BuildContext context, String name) async {
    String first = name; String last = "";
    if (name.contains(' ')) { final parts = name.split(' '); first = parts.first; last = parts.sublist(1).join(' '); }
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Editor Widget");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final target = await showDialog<String>(context: context, builder: (c) {
      final controller = TextEditingController();
      return AlertDialog(title: Text("Create Alias for '$name'"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Enter EXISTING username (target):"), TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")), TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))]);
    });
    if (target == null || target.isEmpty) return;
    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}