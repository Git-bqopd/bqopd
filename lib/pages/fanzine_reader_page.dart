import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../services/view_service.dart';
import '../widgets/fanzine_widget.dart';
import '../widgets/fanzine_layout.dart';
import '../widgets/readers/fanzine_grid_renderer.dart';
import '../widgets/readers/fanzine_list_renderer.dart';
import '../widgets/fanzine_editor_widget.dart';
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

  bool _isLoading = true;
  String? _resolvedFanzineId;
  String? _resolvedShortCode;
  String? _resolvedType;
  List<Map<String, dynamic>> _pages = [];

  bool _twoPagePreference = true;
  bool _isEditingMode = false;
  HeaderMode _headerMode = HeaderMode.fanzine;
  int _targetIndex = 0;

  bool _showGrid = true;
  bool _showList = false;

  BonusRowType? _activeGlobalPanel;

  double _desktopGridWidth = 300.0;
  double _desktopListWidth = 600.0;
  final double _singleViewFixedWidth = 900.0;

  final ItemScrollController _mobileListScrollController = ItemScrollController();
  ScrollController? _desktopGridScrollController;
  final ItemScrollController _desktopListScrollController = ItemScrollController();

  final GlobalKey _gridComponentKey = GlobalKey();
  final GlobalKey _listComponentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _isEditingMode = widget.isEditingMode;
    _initData();
  }

  @override
  void dispose() {
    _desktopGridScrollController?.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    String? targetShortCode = widget.shortCode;
    String? targetId = widget.fanzineId;

    if (targetShortCode == null && targetId == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
        targetShortCode = userDoc.data()?['newFanzine'];
      } else {
        final settings = await FirebaseFirestore.instance.collection('app_settings').doc('main_settings').get();
        targetShortCode = settings.data()?['login_zine_shortcode'];
      }
    }

    if (targetId == null && targetShortCode != null) {
      final fanzineQuery = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('shortCode', isEqualTo: targetShortCode)
          .limit(1)
          .get();
      if (fanzineQuery.docs.isNotEmpty) {
        targetId = fanzineQuery.docs.first.id;
      } else {
        final scDoc = await FirebaseFirestore.instance.collection('shortcodes').doc(targetShortCode.toUpperCase()).get();
        if (scDoc.exists && scDoc.data()?['type'] == 'fanzine') {
          targetId = scDoc.data()?['contentId'];
        }
      }
    }

    _resolvedFanzineId = targetId;
    _resolvedShortCode = targetShortCode;

    if (_resolvedFanzineId != null) {
      _processDeepLink();
      await _fetchFanzineData(_resolvedFanzineId!);
      _updateUrlIfNeeded();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFanzineData(String fanzineId) async {
    try {
      final fanzineDoc = await FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).get();
      if (!fanzineDoc.exists) throw Exception("Fanzine not found");
      final fanzineData = fanzineDoc.data() ?? {};

      _resolvedType = fanzineData['type'] ?? 'fanzine';

      final bool twoPage = fanzineData['twoPage'] ?? true;
      final snapshot = await FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').get();
      final docs = snapshot.docs.map((d) {
        final data = d.data();
        data['__id'] = d.id;
        return data;
      }).toList();
      docs.sort((a, b) => (a['pageNumber'] as int).compareTo(b['pageNumber'] as int));

      if (mounted) {
        setState(() {
          _pages = docs;
          if (_targetIndex > _pages.length) _targetIndex = _pages.length;
          if (_targetIndex == 0) {
            _twoPagePreference = twoPage;
            if (_twoPagePreference) { _showGrid = true; _showList = false; } else { _showGrid = false; _showList = true; }
          }
          _isLoading = false;
        });
      }
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  void _processDeepLink() {
    try {
      final router = GoRouter.of(context);
      final pQuery = router.routerDelegate.currentConfiguration.uri.queryParameters['p'];
      if (pQuery != null) {
        final pageNum = int.tryParse(pQuery);
        if (pageNum != null && pageNum > 0) {
          setState(() { _targetIndex = pageNum; _showGrid = false; _showList = true; _twoPagePreference = false; });
        }
      }
    } catch (_) {}
  }

  void _updateUrlIfNeeded() {
    if (_resolvedShortCode != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final router = GoRouter.of(context);
          final currentLoc = router.routerDelegate.currentConfiguration.uri.toString();
          if (!currentLoc.contains(_resolvedShortCode!) && !_isEditingMode) {
            context.go('/$_resolvedShortCode');
          }
        } catch (_) {}
      });
    }
  }

  void _onDesktopGridTap(int index) {
    bool listWasNotShowing = !_showList;
    setState(() {
      _targetIndex = index;
      _showList = true;
      if (_desktopGridWidth == 900.0) _desktopGridWidth = 300.0;
      if (_desktopListWidth < 300.0) _desktopListWidth = 900.0;
    });
    if (!listWasNotShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_desktopListScrollController.isAttached) {
          _desktopListScrollController.scrollTo(index: _targetIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      });
    }
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

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mobileListScrollController.isAttached) {
        _mobileListScrollController.scrollTo(index: 0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
      if (_desktopListScrollController.isAttached) {
        _desktopListScrollController.scrollTo(index: 0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    });
  }

  void _showLoginHeader() {
    setState(() {
      _headerMode = HeaderMode.login;
      _twoPagePreference = false;
      if (!_showList) {
        _showList = true;
        if (_desktopGridWidth == 900.0) _desktopGridWidth = 300.0;
        if (_desktopListWidth < 300.0) _desktopListWidth = 900.0;
      }
      _targetIndex = 0;
    });
    _scrollToTop();
  }

  void _onAuthSuccess() {
    setState(() => _headerMode = HeaderMode.fanzine);
    _initData();
  }

  Widget _buildHeader({bool isStickerOnly = false}) {
    if (isStickerOnly) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: FanzineWidget(
            fanzineShortCode: _resolvedShortCode,
            isStickerOnly: true,
            onLoginRequested: _showLoginHeader,
          ),
        ),
      );
    }

    if (_isEditingMode && _resolvedFanzineId != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: _resolvedType == 'calendar'
                ? CalendarEditorWidget(folioId: _resolvedFanzineId!)
                : FanzineEditorWidget(fanzineId: _resolvedFanzineId!),
          ),
        ),
      );
    }

    if (_headerMode == HeaderMode.login) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: LoginWidget(
            onTap: () {
              setState(() => _headerMode = HeaderMode.register);
              _scrollToTop();
            },
            onLoginSuccess: _onAuthSuccess,
          ),
        ),
      );
    } else if (_headerMode == HeaderMode.register) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: RegisterWidget(
            onTap: () {
              setState(() => _headerMode = HeaderMode.login);
              _scrollToTop();
            },
            onRegisterSuccess: _onAuthSuccess,
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: FanzineWidget(
          fanzineShortCode: _resolvedShortCode,
          isStickerOnly: false,
          onLoginRequested: _showLoginHeader,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth > 900;

            if (!isDesktop) {
              return _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : FanzineLayout(
                viewMode: _twoPagePreference ? FanzineViewMode.grid : FanzineViewMode.single,
                pages: _pages,
                fanzineId: _resolvedFanzineId ?? '',
                headerWidget: _buildHeader(),
                gridScrollController: ScrollController(),
                listScrollController: _mobileListScrollController,
                initialIndex: _targetIndex,
                viewService: _viewService,
                isEditingMode: _isEditingMode,
                activeGlobalPanel: _activeGlobalPanel,
                onTogglePanel: _handlePanelToggle,
                onSwitchToSingle: (idx) { setState(() { _targetIndex = idx; _twoPagePreference = false; }); },
                onSwitchToGrid: (idx) { setState(() { _targetIndex = idx; _twoPagePreference = true; }); },
              );
            }

            if (_isLoading) return const Center(child: CircularProgressIndicator());
            final bool isSplitView = _showGrid && _showList;
            final bool isSingleGrid = _showGrid && !_showList;

            Widget gridComponent = Container(
              key: _gridComponentKey,
              color: Colors.grey[200],
              child: FanzineGridRenderer(
                pages: _pages,
                headerWidget: _buildHeader(isStickerOnly: isSplitView),
                scrollController: _desktopGridScrollController ??= ScrollController(),
                viewService: _viewService,
                onPageTap: _onDesktopGridTap,
              ),
            );

            Widget listComponent = Container(
              key: _listComponentKey,
              color: Colors.white,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FanzineListRenderer(
                      fanzineId: _resolvedFanzineId ?? '',
                      pages: _pages,
                      headerWidget: _buildHeader(isStickerOnly: false),
                      itemScrollController: _desktopListScrollController,
                      initialIndex: _targetIndex,
                      viewService: _viewService,
                      isEditingMode: _isEditingMode,
                      isDesktopLayout: true,
                      activeGlobalPanel: _activeGlobalPanel,
                      onTogglePanel: _handlePanelToggle,
                      onOpenGrid: null,
                    ),
                  ),
                  if (isSplitView)
                    Positioned(
                      top: 8, right: 8,
                      child: FloatingActionButton.small(
                        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 4,
                        child: const Icon(Icons.close),
                        onPressed: () { setState(() { _showList = false; _activeGlobalPanel = null; }); },
                      ),
                    ),
                ],
              ),
            );

            Widget readerBlock = isSplitView
                ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: _desktopGridWidth, child: gridComponent),
                  _buildDivider((d) {
                    setState(() {
                      if (_desktopGridWidth + d > 100 && _desktopListWidth - d > 300) {
                        _desktopGridWidth += d; _desktopListWidth -= d;
                      }
                    });
                  }),
                  SizedBox(width: _desktopListWidth, child: listComponent),
                ])
                : SizedBox(width: _singleViewFixedWidth, child: isSingleGrid ? gridComponent : listComponent);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: SizedBox()),
                readerBlock,

                if (_activeGlobalPanel != null)
                  Container(
                    width: 400,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(left: BorderSide(color: Colors.black12)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: Colors.grey[100],
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_activeGlobalPanel!.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _activeGlobalPanel = null)),
                            ],
                          ),
                        ),
                        const Expanded(
                          child: Center(child: Text("3rd Column: All panels of this type will list here.")),
                        ),
                      ],
                    ),
                  ),

                const Expanded(child: SizedBox()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDivider(Function(double) onDrag) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(width: 16, color: Colors.grey[300], child: const Center(child: VerticalDivider(thickness: 1, width: 1, color: Colors.grey))),
      ),
    );
  }
}