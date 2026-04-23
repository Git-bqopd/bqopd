import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
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
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;
  String? _lastSyncedTitle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2 + widget.customTabs.length, vsync: this);
    _tabController.addListener(() {
      // Snap back to the top of the scroll view when changing tabs
      if (_tabController.indexIsChanging) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
      }
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _shortcodeController.dispose();
    _titleController.dispose();
    _tabController.dispose();
    _scrollController.dispose();
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
                    SnackBar(content: Text(state.message), backgroundColor: Colors.black87),
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

                  return LayoutBuilder(
                      builder: (context, constraints) {
                        // If the widget is embedded in a bounded layout (like the Grid View envelope),
                        // we disable scrolling so it cleanly cuts off at the bottom.
                        // If unbounded (List View), it can scroll normally.
                        final bool isGridView = constraints.maxHeight != double.infinity;

                        Widget mainContent = Stack(
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
                              clipBehavior: Clip.antiAlias, // Clips overflowing content cleanly at the border radius
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                physics: isGridView ? const NeverScrollableScrollPhysics() : null,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TabBar(
                                      controller: _tabController,
                                      labelColor: Colors.black, // Grayscale
                                      unselectedLabelColor: Colors.grey,
                                      indicatorColor: Colors.black, // Grayscale
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
                            ),
                            if (state.isProcessing)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.white60,
                                  child: const Center(child: CircularProgressIndicator(color: Colors.black)),
                                ),
                              ),
                          ],
                        );

                        if (isGridView) {
                          // Grid View handles its own Manila envelope padding inside the page renderer
                          return mainContent;
                        } else {
                          // List View needs the Manila Envelope injected locally
                          return Container(
                            color: const Color(0xFFF1B255), // Manila Envelope Color
                            padding: const EdgeInsets.all(10.0),
                            child: mainContent,
                          );
                        }
                      }
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

    return Padding(
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
            ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: state.isProcessing
                ? null
                : () {
              bloc.add(UpdateFanzineTitle(_titleController.text));
              if (widget.onSaveCallback != null) {
                widget.onSaveCallback!();
              } else {
                // Safely return to the profile page without overwriting the clean URL
                if (context.canPop()) {
                  context.pop();
                } else {
                  final userProvider = Provider.of<UserProvider>(context, listen: false);
                  final username = userProvider.userProfile?.username;
                  if (username != null) {
                    context.go('/$username');
                  } else {
                    context.go('/');
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey, // Grayscale
                foregroundColor: Colors.white),
            child: const Text("save folio", style: TextStyle(fontWeight: FontWeight.bold)),
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

    return LayoutBuilder(
        builder: (context, constraints) {
          // Adjust layout style if screen width is narrow (Mobile) vs wide (Desktop)
          final bool isCompact = constraints.maxWidth < 600;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('flatplan',
                    textAlign: TextAlign.center,
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

                      // Component 1: Segmented Grid layout preferences (Grayscale)
                      final layoutRow = Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SegmentedButton<String>(
                              showSelectedIcon: false,
                              emptySelectionAllowed: true,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(fontSize: 9),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                selectedBackgroundColor: Colors.grey,
                                selectedForegroundColor: Colors.white,
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
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                selectedBackgroundColor: Colors.grey,
                                selectedForegroundColor: Colors.white,
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
                      );

                      // Component 2: The Cover toggle logic (Grayscale)
                      final coverRow = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("cover", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Transform.scale(
                            scale: 0.7,
                            child: Switch(
                              value: state.fanzine.hasCover,
                              activeColor: Colors.white,
                              activeTrackColor: Colors.grey,
                              inactiveThumbColor: Colors.grey.shade400,
                              inactiveTrackColor: Colors.grey.shade200,
                              onChanged: (val) => bloc.add(ToggleHasCoverRequested(val)),
                            ),
                          ),
                        ],
                      );

                      // Assemble the layout buttons wrapper. Desktop keeps a hard width to align like a table.
                      Widget layoutButtonsWidget = isCompact
                          ? (showLayoutButtons ? FittedBox(fit: BoxFit.scaleDown, child: layoutRow) : const SizedBox.shrink())
                          : SizedBox(width: 280, child: showLayoutButtons ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: layoutRow) : null);

                      // Assemble the action control wrapper. Desktop keeps a hard width to align like a table.
                      Widget controlButtonsWidget = Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCompact)
                            if (num == 1) coverRow else const SizedBox.shrink()
                          else
                            SizedBox(width: 90, child: num == 1 ? coverRow : null),
                          IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 14, color: Colors.black87),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: num > 1 ? () => bloc.add(ReorderPageRequested(page, -1, pages)) : null),
                          const SizedBox(width: 12),
                          IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 14, color: Colors.black87),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: num < ordered.length ? () => bloc.add(ReorderPageRequested(page, 1, pages)) : null),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.close, size: 14, color: Colors.black54), // Grayscale
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: () => bloc.add(TogglePageOrderingRequested(page, false)),
                            tooltip: "unorder",
                          ),
                          if (!isCompact) const SizedBox(width: 8),
                        ],
                      );

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                        child: isCompact
                            ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                SizedBox(width: 24, child: Text('$num.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                Expanded(child: Text(page.templateId != null ? "template page" : "image page", style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                                layoutButtonsWidget,
                              ],
                            ),
                            const SizedBox(height: 4),
                            controlButtonsWidget,
                          ],
                        )
                            : Row(
                          children: [
                            SizedBox(width: 24, child: Text('$num.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Expanded(child: Text(page.templateId != null ? "template page" : "image page", style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                            layoutButtonsWidget,
                            const SizedBox(width: 8),
                            controlButtonsWidget,
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
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isCompact ? 3 : 5, // Better grid on mobile
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
                          child: page.imageUrl == null ? const Center(child: Icon(Icons.auto_awesome_motion, size: 16, color: Colors.grey)) : null,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          );
        }
    );
  }
}