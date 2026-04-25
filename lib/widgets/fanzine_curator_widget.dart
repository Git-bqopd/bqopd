import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/fanzine.dart';
import '../models/fanzine_page.dart';
import '../services/username_service.dart';
import '../services/user_bootstrap.dart';
import '../services/user_provider.dart';
import '../blocs/fanzine_editor_bloc.dart';
import 'base_fanzine_workspace.dart';

class FanzineCuratorWidget extends StatefulWidget {
  final String fanzineId;
  const FanzineCuratorWidget({super.key, required this.fanzineId});

  @override
  State<FanzineCuratorWidget> createState() => _FanzineCuratorWidgetState();
}

class _FanzineCuratorWidgetState extends State<FanzineCuratorWidget> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _shortcodeController = TextEditingController();
  String? _lastSyncedTitle;

  @override
  void dispose() {
    _titleController.dispose();
    _shortcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BaseFanzineWorkspace(
      fanzineId: widget.fanzineId,
      tabs: const [
        Tab(text: "settings", icon: Icon(Icons.settings, size: 20)),
        Tab(text: "order", icon: Icon(Icons.format_list_numbered, size: 20)),
        Tab(text: "OCR / Ent", icon: Icon(Icons.auto_awesome, size: 20)),
      ],
      tabViews: [
            (context, fanzine, pages) => _buildCuratorSettingsTab(context, fanzine),
            (context, fanzine, pages) => _buildCuratorOrderTab(context, pages),
            (context, fanzine, pages) => _buildOCREntitiesTab(context, fanzine, pages),
      ],
    );
  }

  Widget _buildCuratorSettingsTab(BuildContext context, Fanzine fanzine) {
    final bloc = context.read<FanzineEditorBloc>();

    if (_lastSyncedTitle != fanzine.title) {
      _titleController.text = fanzine.title;
      _lastSyncedTitle = fanzine.title;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            onSubmitted: (val) => bloc.add(UpdateFanzineTitle(val)),
            decoration: const InputDecoration(
                labelText: 'fanzine name',
                isDense: true,
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                floatingLabelStyle: TextStyle(color: Colors.black87),
                helperText: "Press enter to save"),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _shortcodeController,
                    decoration: const InputDecoration(
                      hintText: 'paste image shortcode',
                      isDense: true,
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    ))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: () {
                  bloc.add(AddPageRequested(_shortcodeController.text));
                  _shortcodeController.clear();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
                child: const Text('add page')),
          ]),
          const SizedBox(height: 20),
          const Text("COLLABORATORS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Owner: ${fanzine.ownerId == context.read<UserProvider>().currentUserId ? 'You' : fanzine.ownerId}", style: const TextStyle(fontSize: 12)),
                if (fanzine.editors.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text("Editors: ${fanzine.editors.length}", style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Enable two page spread view', style: TextStyle(fontSize: 12)),
            Switch(
                value: fanzine.twoPage,
                activeColor: Colors.grey,
                onChanged: (val) => bloc.add(ToggleTwoPageRequested(val))),
          ]),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('STATUS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text(fanzine.status.name.toUpperCase(),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: fanzine.status == FanzineStatus.live ? Colors.green : Colors.orange)),
            ]),
            Row(children: [
              TextButton(
                  onPressed: () => bloc.add(SoftPublishRequested()),
                  child: const Text('Soft Publish', style: TextStyle(color: Colors.black))),
              Switch(
                  value: fanzine.status == FanzineStatus.live,
                  activeColor: Colors.green,
                  onChanged: (_) => bloc.add(ToggleLiveStatusRequested(fanzine.status.name))),
              const Text('Live', style: TextStyle(fontSize: 12)),
            ])
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              bloc.add(UpdateFanzineTitle(_titleController.text));
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white),
            child: const Text("save curator session", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCuratorOrderTab(BuildContext context, List<FanzinePage> pages) {
    final bloc = context.read<FanzineEditorBloc>();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PAGE ORDER (CURATOR)',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          if (pages.isEmpty)
            const Text('No pages added.',
                style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pages.length,
              itemBuilder: (context, index) {
                final page = pages[index];
                final num = page.pageNumber;

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                  child: Row(
                    children: [
                      Text('$num.',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text("Archival Ingested Page",
                              style: TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis)),
                      IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 14),
                          onPressed: num > 1 ? () => bloc.add(ReorderPageRequested(page, -1, pages)) : null),
                      IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 14),
                          onPressed: num < pages.length ? () => bloc.add(ReorderPageRequested(page, 1, pages)) : null),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOCREntitiesTab(BuildContext context, Fanzine fanzine, List<FanzinePage> pages) {
    if (fanzine.type == FanzineType.folio || fanzine.type == FanzineType.calendar) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Text("Automated OCR and Entity Extraction pipelines are not applicable for manually assembled Folios.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }

    final entities = fanzine.draftEntities;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _Counter(label: "Pages", count: pages.length, color: Colors.blue),
            _Counter(label: "Entities", count: entities.length, color: Colors.green),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          if (entities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Text("No entities detected yet.",
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entities.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) => _EntityRow(name: entities[index]),
            ),
        ],
      ),
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
      Text("$count",
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)),
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