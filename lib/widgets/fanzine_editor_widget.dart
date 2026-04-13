import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blocs/fanzine_editor_bloc.dart';
import '../repositories/fanzine_repository.dart';
import '../services/username_service.dart';

class FanzineEditorWidget extends StatelessWidget {
  final String fanzineId;
  const FanzineEditorWidget({super.key, required this.fanzineId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FanzineEditorBloc(
        repository: RepositoryProvider.of<FanzineRepository>(context),
        fanzineId: fanzineId,
      )..add(LoadFanzineRequested(fanzineId)),
      child: _FanzineEditorView(fanzineId: fanzineId),
    );
  }
}

class _FanzineEditorView extends StatefulWidget {
  final String fanzineId;
  const _FanzineEditorView({required this.fanzineId});

  @override
  State<_FanzineEditorView> createState() => _FanzineEditorViewState();
}

class _FanzineEditorViewState extends State<_FanzineEditorView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _shortcodeController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  late TabController _tabController;
  String? _lastSyncedTitle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _shortcodeController.dispose();
    _titleController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FanzineEditorBloc, FanzineEditorState>(
      listener: (context, state) {
        if (state is FanzineEditorFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      builder: (context, state) {
        if (state is FanzineEditorLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is FanzineEditorLoaded) {
          final data = state.fanzineData;
          final title = data['title'] ?? 'Untitled';
          final shortCode = data['shortCode'];
          final status = data['status'] ?? 'draft';
          final twoPage = data['twoPage'] ?? false;
          final type = data['type'] ?? 'fanzine';
          final hasSourceFile = data.containsKey('sourceFile');
          final List<String> entities =
          List<String>.from(data['draftEntities'] ?? []);

          if (_lastSyncedTitle != title) {
            _titleController.text = title;
            _lastSyncedTitle = title;
          }

          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabBar(
                      controller: _tabController,
                      labelColor: Theme.of(context).primaryColor,
                      unselectedLabelColor: Colors.grey,
                      tabs: const [
                        Tab(text: "Settings", icon: Icon(Icons.settings, size: 20)),
                        Tab(text: "Order", icon: Icon(Icons.format_list_numbered, size: 20)),
                        Tab(text: "OCR / Ent", icon: Icon(Icons.auto_awesome, size: 20)),
                      ],
                    ),
                    _buildTabContent(context, state, data, entities,
                        hasSourceFile, shortCode, twoPage, status, type),
                  ],
                ),
              ),
              if (state.isProcessing)
                Positioned.fill(
                  child: Container(
                    color: Colors.white60,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
        }

        return const Center(child: Text("Error loading editor."));
      },
    );
  }

  Widget _buildTabContent(
      BuildContext context,
      FanzineEditorLoaded state,
      Map<String, dynamic> data,
      List<String> entities,
      bool hasSourceFile,
      String? shortCode,
      bool twoPage,
      String status,
      String type,
      ) {
    switch (_tabController.index) {
      case 0:
        return _buildSettingsTab(
            context, state, data, hasSourceFile, shortCode, twoPage, status);
      case 1:
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PAGE ORDER',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              _PageList(pages: state.pages, onReorder: (doc, delta) {
                context.read<FanzineEditorBloc>().add(
                    ReorderPageRequested(doc, delta, state.pages));
              }),
            ],
          ),
        );
      case 2:
        return _buildOCREntitiesTab(context, state, entities, type);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSettingsTab(
      BuildContext context,
      FanzineEditorLoaded state,
      Map<String, dynamic> data,
      bool hasSourceFile,
      String? shortCode,
      bool twoPage,
      String status,
      ) {
    final bloc = context.read<FanzineEditorBloc>();

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
                labelText: 'Fanzine Name',
                isDense: true,
                border: OutlineInputBorder(),
                helperText: "Press enter to save"),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _shortcodeController,
                    decoration: const InputDecoration(
                        hintText: 'Paste image shortcode',
                        isDense: true,
                        border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: state.isProcessing
                    ? null
                    : () {
                  bloc.add(AddPageRequested(_shortcodeController.text));
                  _shortcodeController.clear();
                },
                child: const Text('Add Page')),
          ]),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shortcode: ${shortCode ?? 'None'}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (shortCode == null)
                TextButton(
                  onPressed: () {},
                  child: const Text("GENERATE SHORTCODE",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                )
            ],
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Has two page spread view', style: TextStyle(fontSize: 12)),
            Switch(
                value: twoPage,
                onChanged: (val) => bloc.add(UpdateFanzineTitle(_titleController.text))),
          ]),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('STATUS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              Text(status.toUpperCase(),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: status == 'live' ? Colors.green : Colors.orange)),
            ]),
            Row(children: [
              TextButton(
                  onPressed: () => bloc.add(SoftPublishRequested()),
                  child: const Text('Soft Publish')),
              Switch(
                  value: status == 'live',
                  onChanged: (_) => bloc.add(ToggleLiveStatusRequested(status))),
              const Text('Live', style: TextStyle(fontSize: 12)),
            ])
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: state.isProcessing
                ? null
                : () => bloc.add(UpdateFanzineTitle(_titleController.text)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white),
            child: const Text("SAVE SETTINGS"),
          ),
        ],
      ),
    );
  }

  Widget _buildOCREntitiesTab(
      BuildContext context, FanzineEditorLoaded state, List<String> entities, String type) {

    if (type == 'folio' || type == 'calendar') {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Text("Automated OCR and Entity Extraction pipelines are not applicable for manually assembled Folios.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _Counter(label: "Pages", count: state.pages.length, color: Colors.blue),
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

  const _Counter(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text("$count",
          style: TextStyle(
              fontWeight: FontWeight.bold, color: color, fontSize: 18)),
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
      stream: FirebaseFirestore.instance
          .collection('usernames')
          .doc(handle)
          .snapshots(),
      builder: (context, snapshot) {
        Widget statusWidget;
        if (!snapshot.hasData) {
          statusWidget = const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snapshot.data!.exists) {
          statusWidget = const Text("Linked",
              style: TextStyle(color: Colors.blue, fontSize: 11));
        } else {
          statusWidget = const Text("Missing",
              style: TextStyle(color: Colors.orange, fontSize: 11));
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
}

class _PageList extends StatelessWidget {
  final List<DocumentSnapshot> pages;
  final Function(DocumentSnapshot, int) onReorder;

  const _PageList({required this.pages, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const Text('No pages added.',
          style: TextStyle(color: Colors.grey, fontSize: 12));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final doc = pages[index];
        final data = doc.data() as Map<String, dynamic>;
        final num = data['pageNumber'] ?? 0;

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
                  child: Text("Page Image",
                      style: TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis)),
              IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 14),
                  onPressed: num > 1 ? () => onReorder(doc, -1) : null),
              IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 14),
                  onPressed: num < pages.length ? () => onReorder(doc, 1) : null),
            ],
          ),
        );
      },
    );
  }
}