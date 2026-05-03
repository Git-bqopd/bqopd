import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../blocs/reader/fanzine_reader_bloc.dart';
import '../services/view_service.dart';
import '../services/user_provider.dart';
import '../widgets/fanzine_widget.dart';
import '../widgets/fanzine_layout.dart';
import '../widgets/readers/fanzine_grid_renderer.dart';
import '../widgets/readers/fanzine_list_renderer.dart';
import '../widgets/readers/panel_column_renderer.dart';
import '../widgets/fanzine_curator_widget.dart';
import '../widgets/fanzine_maker_widget.dart';
import '../widgets/calendar_editor_widget.dart';
import '../widgets/login_widget.dart';
import '../widgets/register_widget.dart';
import '../models/reader_tool.dart';

enum HeaderMode { fanzine, login, register }

class FanzineReaderPage extends StatefulWidget {
  final String? fanzineId;
  final String? shortCode;
  final bool isEditingMode;

  const FanzineReaderPage({
    super.key,
    this.fanzineId,
    this.shortCode,
    this.isEditingMode = false,
  });

  @override
  State<FanzineReaderPage> createState() => _FanzineReaderPageState();
}

class _FanzineReaderPageState extends State<FanzineReaderPage> {
  final ViewService _viewService = ViewService();
  late final FanzineReaderBloc _readerBloc;

  HeaderMode _headerMode = HeaderMode.fanzine;
  int _targetIndex = 0;
  bool _showGrid = true;
  bool _showList = false;

  BonusRowType? _activeGlobalPanel;

  final ItemScrollController _mobileListScrollController = ItemScrollController();
  ScrollController? _desktopGridScrollController;
  final ItemScrollController _desktopListScrollController = ItemScrollController();
  final ItemScrollController _desktopPanelScrollController = ItemScrollController();

  static const double kMaxGridWidth = 600.0;
  static const double kMaxReaderWidth = 800.0;

  @override
  void initState() {
    super.initState();
    _readerBloc = FanzineReaderBloc();

    // Delay initialization until the tree is built so we can read the UserProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initReader();
    });
  }

  void _initReader() {
    final userProvider = context.read<UserProvider>();
    final isInternalStaff = userProvider.isAdmin || userProvider.isModerator || userProvider.isCurator;

    _readerBloc.add(InitializeReaderRequested(
      fanzineId: widget.fanzineId,
      shortCode: widget.shortCode,
      currentUserId: userProvider.currentUserId,
      isInternalStaff: isInternalStaff,
    ));
  }

  @override
  void dispose() {
    _readerBloc.close();
    _desktopGridScrollController?.dispose();
    super.dispose();
  }

  void _processDeepLink() {
    try {
      final router = GoRouter.of(context);
      final pQuery = router.routerDelegate.currentConfiguration.uri.queryParameters['p'];
      if (pQuery != null) {
        final pageNum = int.tryParse(pQuery);
        if (pageNum != null && pageNum > 0) {
          setState(() {
            _targetIndex = pageNum;
            _showGrid = false;
            _showList = true;
          });
        }
      }
    } catch (_) {}
  }

  void _updateUrlIfNeeded(String? resolvedShortCode) {
    if (resolvedShortCode != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final router = GoRouter.of(context);
          final currentLoc = router.routerDelegate.currentConfiguration.uri.toString();
          if (!currentLoc.contains(resolvedShortCode) && !widget.isEditingMode) {
            context.go('/$resolvedShortCode');
          }
        } catch (_) {}
      });
    }
  }

  void _handlePageTap(int index) {
    setState(() {
      _targetIndex = index;
      _showList = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_desktopListScrollController.isAttached) {
        _desktopListScrollController.scrollTo(index: index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
      if (_desktopPanelScrollController.isAttached) {
        _desktopPanelScrollController.scrollTo(index: index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    });
  }

  void _handleCloseList() {
    setState(() {
      _showList = false;
      _activeGlobalPanel = null;
    });
  }

  void _handlePanelToggle(BonusRowType type) {
    setState(() {
      if (_activeGlobalPanel == type) {
        _activeGlobalPanel = null;
      } else {
        _activeGlobalPanel = type;
      }
    });
  }

  void _showLoginHeader() {
    setState(() => _headerMode = HeaderMode.login);
  }

  void _onAuthSuccess() {
    setState(() => _headerMode = HeaderMode.fanzine);
    _initReader();
  }

  Widget _buildHeader(FanzineReaderState state, {bool isStickerOnly = false}) {
    if (isStickerOnly) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: FanzineWidget(
            fanzineShortCode: state.resolvedShortCode,
            isStickerOnly: true,
            onLoginRequested: _showLoginHeader,
          ),
        ),
      );
    }

    if (_headerMode == HeaderMode.login || _headerMode == HeaderMode.register) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Stack(
            children: [
              _headerMode == HeaderMode.login
                  ? LoginWidget(
                onTap: () => setState(() => _headerMode = HeaderMode.register),
                onLoginSuccess: _onAuthSuccess,
              )
                  : RegisterWidget(
                onTap: () => setState(() => _headerMode = HeaderMode.login),
                onRegisterSuccess: _onAuthSuccess,
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.8),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: () => setState(() => _headerMode = HeaderMode.fanzine),
                    tooltip: "Cancel",
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.isEditingMode && state.resolvedFanzineId != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: state.resolvedType == 'calendar'
                ? CalendarEditorWidget(folioId: state.resolvedFanzineId!)
                : (state.resolvedType == 'folio' || state.resolvedType == 'article')
                ? FanzineMakerWidget(fanzineId: state.resolvedFanzineId!)
                : FanzineCuratorWidget(fanzineId: state.resolvedFanzineId!),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: FanzineWidget(
          fanzineShortCode: state.resolvedShortCode,
          isStickerOnly: false,
          onLoginRequested: _showLoginHeader,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _readerBloc,
      child: Scaffold(
        backgroundColor: Colors.grey[200],
        body: SafeArea(
          child: BlocConsumer<FanzineReaderBloc, FanzineReaderState>(
            listener: (context, state) {
              // Once loading completes, process deep links and layout rules
              if (!state.isLoading && !state.isAccessDenied) {
                _processDeepLink();
                _updateUrlIfNeeded(state.resolvedShortCode);

                bool isDesktop = MediaQuery.of(context).size.width > 900;

                // Only override layout logic if we didn't just deep link straight to a page
                if (_targetIndex == 0) {
                  setState(() {
                    if (state.twoPagePreference) {
                      if (widget.isEditingMode && isDesktop) {
                        _showGrid = true;
                        _showList = true;
                      } else {
                        _showGrid = true;
                        _showList = false;
                      }
                    } else {
                      _showGrid = false;
                      _showList = true;
                    }
                  });
                }
              }
            },
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state.isAccessDenied) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text("Private Work", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text("This content has not been published yet.", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.go('/'),
                        child: const Text("Go Home"),
                      ),
                    ],
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final bool isDesktop = constraints.maxWidth > 900;

                  // --- MOBILE LAYOUT ---
                  if (!isDesktop) {
                    if (!_showList) {
                      return FanzineGridRenderer(
                        pages: state.pages,
                        headerWidget: widget.isEditingMode
                            ? GestureDetector(
                          onTap: () {
                            setState(() {
                              _showList = true;
                              _targetIndex = 0;
                            });
                          },
                          child: AbsorbPointer(
                            child: _buildHeader(state, isStickerOnly: true),
                          ),
                        )
                            : _buildHeader(state, isStickerOnly: false),
                        scrollController: ScrollController(),
                        viewService: _viewService,
                        hasCover: state.hasCover,
                        onPageTap: _handlePageTap,
                      );
                    } else {
                      return FanzineLayout(
                        viewMode: FanzineViewMode.single,
                        pages: state.pages,
                        fanzineId: state.resolvedFanzineId ?? '',
                        fanzineType: state.resolvedType,
                        headerWidget: _buildHeader(state),
                        gridScrollController: ScrollController(),
                        listScrollController: _mobileListScrollController,
                        initialIndex: _targetIndex,
                        viewService: _viewService,
                        isEditingMode: widget.isEditingMode,
                        activeGlobalPanel: _activeGlobalPanel,
                        onTogglePanel: _handlePanelToggle,
                        onSwitchToSingle: (idx) { setState(() => _targetIndex = idx); },
                        onOpenGrid: _handleCloseList,
                      );
                    }
                  }

                  // --- DESKTOP LAYOUT ---
                  final double availableWidth = constraints.maxWidth;
                  final bool isPanelOpen = _showList && _activeGlobalPanel != null;

                  double gridWidth = 0;
                  double listWidth = 0;

                  if (_showGrid && !_showList) {
                    gridWidth = availableWidth.clamp(0.0, kMaxGridWidth * 1.5);
                  } else if (_showGrid && _showList) {
                    gridWidth = (availableWidth * 0.3).clamp(300.0, 500.0);
                    listWidth = (availableWidth * 0.45).clamp(400.0, 800.0);
                  } else if (!_showGrid && _showList) {
                    listWidth = (availableWidth * 0.6).clamp(600.0, kMaxReaderWidth);
                  }

                  return Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_showGrid)
                          SizedBox(
                            width: gridWidth,
                            child: Container(
                              color: Colors.grey[200],
                              child: FanzineGridRenderer(
                                pages: state.pages,
                                headerWidget: _buildHeader(state, isStickerOnly: _showList),
                                scrollController: _desktopGridScrollController ??= ScrollController(),
                                viewService: _viewService,
                                hasCover: state.hasCover,
                                onPageTap: _handlePageTap,
                              ),
                            ),
                          ),

                        if (_showList)
                          SizedBox(
                            width: listWidth,
                            child: Container(
                              color: Colors.white,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: FanzineListRenderer(
                                      fanzineId: state.resolvedFanzineId ?? '',
                                      fanzineType: state.resolvedType,
                                      pages: state.pages,
                                      headerWidget: _buildHeader(state, isStickerOnly: false),
                                      itemScrollController: _desktopListScrollController,
                                      initialIndex: _targetIndex,
                                      viewService: _viewService,
                                      isEditingMode: widget.isEditingMode,
                                      isDesktopLayout: true,
                                      activeGlobalPanel: _activeGlobalPanel,
                                      onTogglePanel: _handlePanelToggle,
                                      onOpenGrid: _handleCloseList,
                                    ),
                                  ),
                                  if (_showList && _showGrid)
                                    Positioned(
                                      top: 8, right: 8,
                                      child: FloatingActionButton.small(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black,
                                        elevation: 4,
                                        onPressed: _handleCloseList,
                                        child: const Icon(Icons.close),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                        if (isPanelOpen)
                          Expanded(
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                border: Border(left: BorderSide(color: Colors.black12)),
                              ),
                              child: PanelColumnRenderer(
                                fanzineId: state.resolvedFanzineId ?? '',
                                fanzineTitle: state.fanzineTitle,
                                pages: state.pages,
                                activePanel: _activeGlobalPanel!,
                                viewService: _viewService,
                                isEditingMode: widget.isEditingMode,
                                itemScrollController: _desktopPanelScrollController,
                                onClose: () => setState(() => _activeGlobalPanel = null),
                                initialIndex: _targetIndex,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}