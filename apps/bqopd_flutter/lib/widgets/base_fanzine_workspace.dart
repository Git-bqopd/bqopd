import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../blocs/fanzine_editor_bloc.dart';
import '../repositories/fanzine_repository.dart';
import '../repositories/pipeline_repository.dart';
import '../services/user_provider.dart';
import '../models/fanzine.dart';
import '../models/fanzine_page.dart';

/// A universal UI shell for Fanzine Editor configurations (Curator, Maker, Editor).
/// This widget provides the Manila Envelope container and TabBar structure,
/// but expects the specific implementation of tabs to be passed in by the child.
class BaseFanzineWorkspace extends StatefulWidget {
  final String fanzineId;
  final List<Tab> tabs;
  final List<Widget Function(BuildContext context, Fanzine fanzine, List<FanzinePage> pages)> tabViews;
  final VoidCallback? onSaveCallback;

  const BaseFanzineWorkspace({
    super.key,
    required this.fanzineId,
    required this.tabs,
    required this.tabViews,
    this.onSaveCallback,
  });

  @override
  State<BaseFanzineWorkspace> createState() => _BaseFanzineWorkspaceState();
}

class _BaseFanzineWorkspaceState extends State<BaseFanzineWorkspace> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.tabs.length, vsync: this);
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
        pipelineRepository: RepositoryProvider.of<PipelineRepository>(context),
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

                  return LayoutBuilder(
                      builder: (context, constraints) {
                        // If embedded in a bounded layout (Grid View envelope), disable inner scrolling.
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
                              clipBehavior: Clip.antiAlias,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                physics: isGridView ? const NeverScrollableScrollPhysics() : null,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TabBar(
                                      controller: _tabController,
                                      labelColor: Colors.black,
                                      unselectedLabelColor: Colors.grey,
                                      indicatorColor: Colors.black,
                                      tabs: widget.tabs,
                                    ),
                                    widget.tabViews[_tabController.index](context, fanzine, pages),
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
                          return mainContent;
                        } else {
                          return Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFF1B255),
                              borderRadius: BorderRadius.zero,
                            ),
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
}