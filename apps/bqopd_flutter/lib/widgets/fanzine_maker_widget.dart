import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_core/bqopd_core.dart';
import 'package:bqopd_state/bqopd_state.dart';

// Extracted Tabs
import 'editor_tabs/maker_settings_tab.dart';
import 'editor_tabs/maker_order_tab.dart';
import 'editor_tabs/maker_upload_tab.dart';

class FanzineMakerWidget extends StatefulWidget {
  final String fanzineId;
  const FanzineMakerWidget({super.key, required this.fanzineId});

  @override
  State<FanzineMakerWidget> createState() => _FanzineMakerWidgetState();
}

class _FanzineMakerWidgetState extends State<FanzineMakerWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Maker has 3 tabs
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
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
                                      tabs: const [
                                        Tab(text: "settings", icon: Icon(Icons.settings, size: 20)),
                                        Tab(text: "order", icon: Icon(Icons.format_list_numbered, size: 20)),
                                        Tab(text: "upload", icon: Icon(Icons.upload, size: 20)),
                                      ],
                                    ),
                                    _buildActiveTab(context, fanzine, pages),
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

  Widget _buildActiveTab(BuildContext context, Fanzine fanzine, List<FanzinePage> pages) {
    switch (_tabController.index) {
      case 0: return MakerSettingsTab(fanzineId: widget.fanzineId, fanzine: fanzine);
      case 1: return MakerOrderTab(fanzine: fanzine, pages: pages);
      case 2: return MakerUploadTab(fanzineId: widget.fanzineId, folioTitle: fanzine.title);
      default: return const SizedBox.shrink();
    }
  }
}