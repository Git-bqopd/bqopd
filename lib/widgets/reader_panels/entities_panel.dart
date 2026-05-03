import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_bootstrap.dart';
import '../../services/username_service.dart';

class EntitiesPanel extends StatelessWidget {
  final String text;
  final bool isEditingMode;

  const EntitiesPanel({
    super.key,
    required this.text,
    this.isEditingMode = false,
  });

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
        const Text("PAGE ENTITIES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        if (entities.isEmpty)
          const Text("No entity links found in page text.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entities.length,
            separatorBuilder: (c, i) => const SizedBox(height: 8),
            itemBuilder: (c, i) => EntityRow(name: entities[i], isEditingMode: isEditingMode),
          ),
      ],
    );
  }
}

class EntityRow extends StatelessWidget {
  final String name;
  final bool isEditingMode;

  const EntityRow({
    super.key,
    required this.name,
    this.isEditingMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final handle = normalizeHandle(name);

    return StreamBuilder<DocumentSnapshot>(
      // We look up the exact handle to get the unified profile data
      stream: FirebaseFirestore.instance.collection('profiles').doc(handle).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Card(
              elevation: 0,
              child: ListTile(
                leading: CircularProgressIndicator(),
                title: Text("Loading..."),
              )
          );
        }

        final bool exists = snapshot.hasData && snapshot.data!.exists;
        final data = exists ? snapshot.data!.data() as Map<String, dynamic> : null;

        // If it doesn't exist and we are just reading, hide it.
        if (!exists && !isEditingMode) {
          return const SizedBox.shrink();
        }

        final displayName = data?['displayName'] ?? name;
        final bio = data?['bio'] ?? '';
        final photoUrl = data?['photoUrl'] ?? '';

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.black.withValues(alpha: 0.1))
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.grey[200],
              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            title: Row(
              children: [
                Expanded(child: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold))),
                if (!exists && isEditingMode)
                  const Text("UNREGISTERED", style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold))
              ],
            ),
            subtitle: Text(
                exists ? (bio.isNotEmpty ? bio : 'No bio available.') : 'This entity does not have a profile yet.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])
            ),
            trailing: isEditingMode
                ? const Icon(Icons.edit_note, color: Colors.indigo)
                : const Icon(Icons.chevron_right),
            onTap: () {
              if (isEditingMode) {
                _showEditorOptions(context, name, exists);
              } else {
                context.push('/$handle');
              }
            },
          ),
        );
      },
    );
  }

  void _showEditorOptions(BuildContext context, String entityName, bool exists) {
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                      "Editor Options: $entityName",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                  ),
                ),
                const Divider(height: 1),
                if (!exists)
                  ListTile(
                    leading: const Icon(Icons.person_add, color: Colors.green),
                    title: const Text("Create Managed Profile"),
                    subtitle: const Text("Generate a blank archival profile for this entity."),
                    onTap: () {
                      Navigator.pop(context);
                      _createProfile(context, entityName);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.link, color: Colors.orange),
                  title: const Text("Create Redirection Alias"),
                  subtitle: const Text("Point this name to a different, existing profile."),
                  onTap: () {
                    Navigator.pop(context);
                    _createAlias(context, entityName);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        }
    );
  }

  Future<void> _createProfile(BuildContext context, String name) async {
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
        bio: "Profile bio coming soon.",
        explicitHandle: expectedHandle,
      );
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
      return AlertDialog(
          title: Text("Create Alias for '$name'"),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Enter EXISTING username (target):"),
                TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))
              ]
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))
          ]
      );
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