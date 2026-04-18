import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/fanzine_editor_bloc.dart';
import '../repositories/fanzine_repository.dart';
import '../models/fanzine.dart';
import '../models/fanzine_page.dart';

/// A universal wrapper for Fanzine Editor configurations (Curator, Maker, Editor).
/// Provides the Settings and Order tabs automatically while allowing flexible custom tabs.
class BaseFanzineWorkspace extends StatefulWidget {
  final String fanzineId;
  final List<Tab> customTabs;
  final List<Widget Function(BuildContext context, Fanzine fanzine, List<FanzinePage> pages)> customTabViews;
  final VoidCallback? onSaveCallback;

  const BaseFanzineWorkspace({
    super.key,
    required this.fanzineId,
    this.customTabs = const [],
    this.customTabViews = const [],
    this.onSaveCallback,
  });

  @override
  State<BaseFanzineWorkspace> createState() => _BaseFanzineWorkspaceState();
}

class _BaseFanzineWorkspaceState extends State<BaseFanzineWorkspace> with SingleTickerProviderStateMixin {
  final TextEditingController _shortcodeController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  late TabController _tabController;
  String? _lastSyncedTitle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2 + widget.customTabs.length, vsync: this);
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
    return BlocProvider(
      create: (context) => FanzineEditorBloc(
        repository: RepositoryProvider.of<FanzineRepository>(context),
        fanzineId: widget.fanzineId,
      )..add(LoadFanzineRequested(widget.fanzineId)),
      child: Builder(
          builder: (context) {
            return BlocConsumer<FanzineEditorBloc, FanzineEditorState>(
              listener: (context, state) {
                if (state is FanzineEditorFailure) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(state.message), backgroundColor: Colors.red),
                  );
                }
              },
              builder: (context, state) {
                if (state is FanzineEditorLoading || state is FanzineEditorInitial) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is FanzineEditorLoaded) {
                  final fanzine = state.fanzine;
                  final pages = state.pages;

                  if (_lastSyncedTitle != fanzine.title) {
                    _titleController.text = fanzine.title;
                    _lastSyncedTitle = fanzine.title;
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
                              isScrollable: widget.customTabs.length > 2, // Safety fallback
                              tabs: [
                                const Tab(text: "Settings", icon: Icon(Icons.settings, size: 20)),
                                const Tab(text: "Order", icon: Icon(Icons.format_list_numbered, size: 20)),
                                ...widget.customTabs,
                              ],
                            ),
                            _buildTabContent(context, state, fanzine, pages),
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

                return const Center(child: Text("Error loading workspace."));
              },
            );
          }
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, FanzineEditorLoaded state, Fanzine fanzine, List<FanzinePage> pages) {
    if (_tabController.index == 0) {
      return _buildSettingsTab(context, state, fanzine);
    } else if (_tabController.index == 1) {
      return _buildOrderTab(context, state, pages);
    } else {
      final customIndex = _tabController.index - 2;
      if (customIndex >= 0 && customIndex < widget.customTabViews.length) {
        return widget.customTabViews[customIndex](context, fanzine, pages);
      }
      return const SizedBox.shrink();
    }
  }

  Widget _buildSettingsTab(BuildContext context, FanzineEditorLoaded state, Fanzine fanzine) {
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
              Text('Shortcode: ${fanzine.shortCode ?? 'None'}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (fanzine.shortCode == null)
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
                value: fanzine.twoPage,
                onChanged: (val) => bloc.add(ToggleTwoPageRequested(val))),
          ]),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('STATUS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              Text(fanzine.status.name.toUpperCase(),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: fanzine.status == FanzineStatus.live ? Colors.green : Colors.orange)),
            ]),
            Row(children: [
              TextButton(
                  onPressed: () => bloc.add(SoftPublishRequested()),
                  child: const Text('Soft Publish')),
              Switch(
                  value: fanzine.status == FanzineStatus.live,
                  onChanged: (_) => bloc.add(ToggleLiveStatusRequested(fanzine.status.name))),
              const Text('Live', style: TextStyle(fontSize: 12)),
            ])
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: state.isProcessing
                ? null
                : () {
              bloc.add(UpdateFanzineTitle(_titleController.text));
              if (widget.onSaveCallback != null) widget.onSaveCallback!();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white),
            child: const Text("SAVE SETTINGS", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTab(BuildContext context, FanzineEditorLoaded state, List<FanzinePage> pages) {
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
                          child: Text("Page Image",
                              style: TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis)),
                      IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 14),
                          onPressed: num > 1 ? () {
                            context.read<FanzineEditorBloc>().add(ReorderPageRequested(page, -1, pages));
                          } : null),
                      IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 14),
                          onPressed: num < pages.length ? () {
                            context.read<FanzineEditorBloc>().add(ReorderPageRequested(page, 1, pages));
                          } : null),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}