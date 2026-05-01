import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../blocs/curator_workbench/curator_workbench_bloc.dart';
import '../repositories/fanzine_repository.dart';
import '../repositories/pipeline_repository.dart';
import '../services/user_bootstrap.dart';
import '../services/username_service.dart';

class CuratorWorkbenchWidget extends StatelessWidget {
  final String fanzineId;

  const CuratorWorkbenchWidget({super.key, required this.fanzineId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CuratorWorkbenchBloc(
        fanzineRepository: RepositoryProvider.of<FanzineRepository>(context),
        pipelineRepository: RepositoryProvider.of<PipelineRepository>(context),
        fanzineId: fanzineId,
      )..add(LoadWorkbenchRequested(fanzineId)),
      child: _CuratorWorkbenchView(fanzineId: fanzineId),
    );
  }
}

class _CuratorWorkbenchView extends StatefulWidget {
  final String fanzineId;
  const _CuratorWorkbenchView({required this.fanzineId});

  @override
  State<_CuratorWorkbenchView> createState() => _CuratorWorkbenchViewState();
}

class _CuratorWorkbenchViewState extends State<_CuratorWorkbenchView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _textController = TextEditingController();
  String _currentImageUrl = '';
  bool _isLoadingImage = false;
  String? _lastLoadedPageId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _refreshImageUrl(Map<String, dynamic> data) async {
    if (!mounted) return;
    setState(() => _isLoadingImage = true);

    String url = data['imageUrl'] ?? '';
    final storagePath = data['storagePath'];
    if (storagePath != null && storagePath.toString().isNotEmpty) {
      try {
        url = await FirebaseStorage.instance.ref(storagePath).getDownloadURL();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _currentImageUrl = url;
        _isLoadingImage = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CuratorWorkbenchBloc, CuratorWorkbenchState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red),
          );
        }

        if (state.pages.isNotEmpty) {
          final currentPage = state.pages[state.currentIndex];
          if (_lastLoadedPageId != currentPage.id) {
            final data = currentPage.data() as Map<String, dynamic>;
            _textController.text = data['text_processed'] ?? data['text_raw'] ?? data['text'] ?? '';
            _refreshImageUrl(data);
            _lastLoadedPageId = currentPage.id;
            context.read<CuratorWorkbenchBloc>().add(AnalyzeEntitiesRequested(_textController.text));
          }
        }
      },
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final bool hasPages = state.pages.isNotEmpty;
        final bloc = context.read<CuratorWorkbenchBloc>();

        int readyCount = 0; int queuedCount = 0; int completeCount = 0; int errorCount = 0;
        for (var doc in state.pages) {
          final s = doc.data() as Map<String, dynamic>;
          final status = s['status'];
          if (status == 'ready') {
            readyCount++;
          } else if (status == 'queued') {
            queuedCount++;
          } else if (status == 'ocr_complete' || status == 'complete') {
            completeCount++;
          } else if (status == 'error') {
            errorCount++;
          }
        }

        Widget imagePanel = Container(
          color: Colors.grey[900],
          child: _isLoadingImage
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : (hasPages
              ? InteractiveViewer(child: Image.network(_currentImageUrl, fit: BoxFit.contain))
              : const Center(child: Text("No Image", style: TextStyle(color: Colors.white)))),
        );

        Widget rightPanel = Column(
          children: [
            Container(
              color: Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: state.currentIndex > 0 ? () => bloc.add(ChangePageRequested(state.currentIndex - 1)) : null,
                  ),
                  Text("Page ${state.currentIndex + 1} / ${state.pages.length}"),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: state.currentIndex < state.pages.length - 1 ? () => bloc.add(ChangePageRequested(state.currentIndex + 1)) : null,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: state.isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                    onPressed: state.isSaving ? null : () => bloc.add(SaveCurrentPageRequested(_textController.text)),
                  )
                ],
              ),
            ),
            TabBar(controller: _tabController, tabs: const [Tab(text: "Pipeline"), Tab(text: "Editor"), Tab(text: "Entities")]),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("Pipeline Status", style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("Status: ${state.pipelineStatus}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                          _Counter(label: "Ready", count: readyCount, color: Colors.blue),
                          _Counter(label: "Queued", count: queuedCount, color: Colors.orange),
                          _Counter(label: "Done", count: completeCount, color: Colors.green),
                          _Counter(label: "Error", count: errorCount, color: Colors.red),
                        ]),
                        const SizedBox(height: 20),
                        ElevatedButton(onPressed: () => bloc.add(TriggerOcrRequested()), child: const Text("Run Step 2: Batch OCR")),
                        const SizedBox(height: 10),
                        OutlinedButton(onPressed: () => bloc.add(TriggerFinalizeRequested()), child: const Text("Run Step 3: Finalize")),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      expands: true,
                      onChanged: (val) => bloc.add(AnalyzeEntitiesRequested(val)),
                      decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Transcribe..."),
                    ),
                  ),
                  state.isValidatingEntities
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.detectedEntities.length,
                    separatorBuilder: (c, i) => const Divider(),
                    itemBuilder: (context, i) {
                      final e = state.detectedEntities[i];
                      return _EntityRow(
                          name: e['name'],
                          status: e['status'],
                          redirect: e['redirect']
                      );
                    },
                  )
                ],
              ),
            )
          ],
        );

        return Scaffold(
          body: LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;
            return Column(
              children: [
                Expanded(
                  child: isWide
                      ? Row(children: [Expanded(child: imagePanel), Expanded(child: rightPanel)])
                      : Column(children: [Expanded(child: imagePanel), Expanded(child: rightPanel)]),
                ),
                Container(
                  height: 50,
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () => bloc.add(SoftPublishWorkbenchRequested()),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                        child: const Text("Soft Publish"),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () {
                          FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).update({'status': 'live'});
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text("Mark Live"),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                )
              ],
            );
          }),
        );
      },
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
  final String status;
  final String? redirect;

  const _EntityRow({required this.name, required this.status, this.redirect});

  @override
  Widget build(BuildContext context) {
    final handle = normalizeHandle(name);

    Widget statusWidget;
    if (status == 'exists') {
      statusWidget = Text('/$handle', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline));
    } else if (status == 'alias') {
      statusWidget = Text('/$handle -> /${redirect ?? 'unknown'}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline));
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
  }

  Future<void> _createProfile(BuildContext context, String name) async {
    String first = name; String last = "";
    if (name.contains(' ')) { final parts = name.split(' '); first = parts.first; last = parts.sublist(1).join(' '); }
    final expectedHandle = normalizeHandle(name);
    try {
      await createManagedProfile(
        firstName: first,
        lastName: last,
        bio: "Auto-created from Editor Widget",
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