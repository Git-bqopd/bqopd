import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/fanzine.dart';
import '../../services/username_service.dart';
import '../../services/user_bootstrap.dart';
import '../../blocs/fanzine_editor_bloc.dart';

class OcrEntitiesTab extends StatelessWidget {
  final Fanzine fanzine;

  const OcrEntitiesTab({super.key, required this.fanzine});

  @override
  Widget build(BuildContext context) {
    if (fanzine.type == FanzineType.folio || fanzine.type == FanzineType.calendar) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Text("Automated OCR and Entity Extraction pipelines are not applicable for manually assembled Folios.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }

    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('images').where('usedInFanzines', arrayContains: fanzine.id).snapshots(),
        builder: (context, snapshot) {
          int rawDone = 0;
          int masterVerified = 0;
          int linkedPending = 0;

          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (data['text_raw'] != null && data['text_raw'].toString().isNotEmpty) rawDone++;
              if (data['text_corrected'] != null && data['needs_ai_cleaning'] != true) masterVerified++;
              if (data['needs_linking'] == true) linkedPending++;
            }
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Counter(label: "Raw Done", count: rawDone, color: Colors.blue),
                      _Counter(label: "Master Verified", count: masterVerified, color: Colors.green),
                      _Counter(label: "Linked Pending", count: linkedPending, color: Colors.orange),
                    ]
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                    onPressed: () => context.read<FanzineEditorBloc>().add(TriggerAiCleanRequested()),
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text("Step 2: AI Clean")
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                    onPressed: () => context.read<FanzineEditorBloc>().add(TriggerGenerateLinksRequested()),
                    icon: const Icon(Icons.link),
                    label: const Text("Step 3: Generate Links")
                ),
                const SizedBox(height: 24),
                const Divider(),
                if (fanzine.draftEntities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Text("No entities detected yet.",
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: fanzine.draftEntities.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (context, index) => _EntityRow(name: fanzine.draftEntities[index]),
                  ),
              ],
            ),
          );
        }
    );
  }
}

class _Counter extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _Counter({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text("$count", style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)),
      Text(label, style: const TextStyle(fontSize: 10))
    ]);
  }
}

class _EntityRow extends StatelessWidget {
  final String name;
  const _EntityRow({required this.name});

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
          statusWidget = Text(linkText,
              style: const TextStyle(
                  color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline));
        } else {
          statusWidget = Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
                onPressed: () => _createProfile(context, name),
                child: const Text("Create", style: TextStyle(color: Colors.green, fontSize: 11))),
            TextButton(
                onPressed: () => _createAlias(context, name),
                child: const Text("Alias", style: TextStyle(color: Colors.orange, fontSize: 11))),
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
    String first = name;
    String last = "";
    if (name.contains(' ')) {
      final parts = name.split(' ');
      first = parts.first;
      last = parts.sublist(1).join(' ');
    }
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
    final target = await showDialog<String>(
        context: context,
        builder: (c) {
          final controller = TextEditingController();
          return AlertDialog(
              title: Text("Create Alias for '$name'"),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Enter EXISTING username (target):"),
                TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
                TextButton(
                    onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))
              ]);
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