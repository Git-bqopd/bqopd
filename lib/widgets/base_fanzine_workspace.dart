import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../blocs/fanzine_editor_bloc.dart';
import '../repositories/fanzine_repository.dart';
import '../services/user_provider.dart';
import '../models/fanzine.dart';
import '../models/fanzine_page.dart';

/// A universal wrapper for Fanzine Editor configurations (Curator, Maker, Editor).
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
    final userProvider = Provider.of<UserProvider>(context);

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

                  if (!userProvider.canEditFanzine(fanzine)) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text("you do not have permission to edit this work."),
                      ),
                    );
                  }

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
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TabBar(
                              controller: _tabController,
                              labelColor: Theme.of(context).primaryColor,
                              unselectedLabelColor: Colors.grey,
                              tabs: [
                                const Tab(text: "settings", icon: Icon(Icons.settings, size: 20)),
                                const Tab(text: "order", icon: Icon(Icons.format_list_numbered, size: 20)),
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

                return const Center(child: Text("error loading workspace."));
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
              labelText: 'fanzine name',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
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
            child: const Text("save settings", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  bool _isPage5x8(FanzinePage page) {
    if (page.templateId != null) return true;
    final w = page.width;
    final h = page.height;
    if (w != null && h != null) {
      final ratio = w / h;
      return ratio >= 0.58 && ratio <= 0.67;
    }
    return false;
  }

  Widget _buildOrderTab(BuildContext context, FanzineEditorLoaded state, List<FanzinePage> pages) {
    final bloc = context.read<FanzineEditorBloc>();

    final fullPages = pages.where((p) => _isPage5x8(p)).toList();
    final ordered = fullPages.where((p) => p.pageNumber > 0).toList();
    final unordered = fullPages.where((p) => p.pageNumber == 0).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('page order',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
          const SizedBox(height: 8),
          if (ordered.isEmpty)
            const Text('no pages in the sequence.',
                style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ordered.length,
              itemBuilder: (context, index) {
                final page = ordered[index];
                final num = page.pageNumber;
                final bool showLayoutButtons = !(num == 1 && state.fanzine.hasCover);

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                  child: Row(
                    children: [
                      SizedBox(width: 24, child: Text('$num.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      Expanded(
                          child: Text(page.templateId != null ? "template page" : "image page",
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis)),

                      SizedBox(
                        width: 280, // Fixed width column for layout buttons
                        child: showLayoutButtons ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  emptySelectionAllowed: true,
                                  style: SegmentedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 9),
                                      padding: const EdgeInsets.symmetric(horizontal: 6)
                                  ),
                                  segments: const [
                                    ButtonSegment(value: 'start', label: Text('start')),
                                    ButtonSegment(value: 'end', label: Text('end')),
                                  ],
                                  selected: page.spreadPosition != null ? {page.spreadPosition!} : <String>{},
                                  onSelectionChanged: (sel) {
                                    final val = sel.isEmpty ? null : sel.first;
                                    bloc.add(UpdatePageLayoutRequested(page, val, page.sidePreference, pages));
                                  }
                              ),
                              const SizedBox(width: 4),
                              SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  emptySelectionAllowed: false,
                                  style: SegmentedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 9),
                                      padding: const EdgeInsets.symmetric(horizontal: 6)
                                  ),
                                  segments: const [
                                    ButtonSegment(value: 'left', label: Text('left')),
                                    ButtonSegment(value: 'either', label: Text('either')),
                                    ButtonSegment(value: 'right', label: Text('right')),
                                  ],
                                  selected: {page.sidePreference},
                                  onSelectionChanged: (sel) {
                                    bloc.add(UpdatePageLayoutRequested(page, page.spreadPosition, sel.first, pages));
                                  }
                              ),
                            ],
                          ),
                        ) : null, // Uses null instead of shrink() to maintain column width
                      ),

                      const SizedBox(width: 8),

                      SizedBox(
                        width: 90, // Fixed width column for the cover switch
                        child: (num == 1) ? Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text("cover", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Transform.scale(
                              scale: 0.7,
                              child: Switch(
                                value: state.fanzine.hasCover,
                                onChanged: (val) => bloc.add(ToggleHasCoverRequested(val)),
                              ),
                            ),
                          ],
                        ) : null, // Uses null instead of shrink() to maintain column width
                      ),

                      IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 14),
                          onPressed: num > 1 ? () => bloc.add(ReorderPageRequested(page, -1, pages)) : null),
                      IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 14),
                          onPressed: num < ordered.length ? () => bloc.add(ReorderPageRequested(page, 1, pages)) : null),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14, color: Colors.red),
                        onPressed: () => bloc.add(TogglePageOrderingRequested(page, false)),
                        tooltip: "unorder",
                      ),
                    ],
                  ),
                );
              },
            ),

          if (unordered.isNotEmpty) ...[
            const SizedBox(height: 32),
            const Text('unordered full pages',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                childAspectRatio: 0.625,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: unordered.length,
              itemBuilder: (context, index) {
                final page = unordered[index];
                return GestureDetector(
                  onTap: () => bloc.add(TogglePageOrderingRequested(page, true)),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      image: page.imageUrl != null ? DecorationImage(image: NetworkImage(page.imageUrl!), fit: BoxFit.cover) : null,
                    ),
                    child: page.imageUrl == null ? const Center(child: Icon(Icons.auto_awesome_motion, size: 16)) : null,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}