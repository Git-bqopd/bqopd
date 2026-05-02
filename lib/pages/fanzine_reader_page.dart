import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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

  bool _isLoading = true;
  bool _isAccessDenied = false;
  String? _resolvedFanzineId;
  String? _resolvedShortCode;
  String? _resolvedType;
  String _fanzineTitle = 'Untitled';
  List<Map<String, dynamic>> _pages = [];

  bool _twoPagePreference = true;
  bool _hasCover = true;
  bool _isEditingMode = false;
  HeaderMode _headerMode = HeaderMode.fanzine;
  int _targetIndex = 0;

  bool _showGrid = true;
  bool _showList = false;

  BonusRowType? _activeGlobalPanel;

  // Stream subscriptions for real-time updates
  StreamSubscription? _fanzineSubscription;
  StreamSubscription? _pagesSubscription;

  final ItemScrollController _mobileListScrollController = ItemScrollController();
  ScrollController? _desktopGridScrollController;
  final ItemScrollController _desktopListScrollController = ItemScrollController();
  final ItemScrollController _desktopPanelScrollController = ItemScrollController();

  static const double kMaxGridWidth = 600.0;
  static const double kMaxReaderWidth = 800.0;

  @override
  void initState() {
    super.initState();
    _isEditingMode = widget.isEditingMode;
    _initData();
  }

  @override
  void dispose() {
    _fanzineSubscription?.cancel();
    _pagesSubscription?.cancel();
    _desktopGridScrollController?.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isAccessDenied = false;
    });

    String? targetShortCode = widget.shortCode;
    String? targetId = widget.fanzineId;

    if (targetShortCode == null && targetId == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
        if (userDoc.exists) {
          targetShortCode = userDoc.data()?['newFanzine'];
        }
      }
      if (targetShortCode == null) {
        final settings = await FirebaseFirestore.instance.collection('app_settings').doc('main_settings').get();
        if (settings.exists) {
          targetShortCode = settings.data()?['login_zine_shortcode'];
        }
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
      _setupListeners(_resolvedFanzineId!);
      _updateUrlIfNeeded();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Sets up real-time Firestore listeners for fanzine metadata and pages.
  void _setupListeners(String fanzineId) {
    _fanzineSubscription?.cancel();
    _fanzineSubscription = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(fanzineId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final fanzineData = doc.data() ?? {};

      // --- SECURITY CHECK: isLive logic for Public vs Staff ---
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final bool isLive = fanzineData['isLive'] ?? false;
      final String ownerId = fanzineData['ownerId'] ?? fanzineData['editorId'] ?? '';
      final List<String> editors = List<String>.from(fanzineData['editors'] ?? []);
      final String? currentUid = userProvider.currentUserId;

      // Internal Staff (Admin/Mod/Curator) or Creator (Owner/Editor) can always see it.
      final bool isInternalStaff = userProvider.isModerator || userProvider.isAdmin || userProvider.isCurator;
      final bool isAuthorizedCreator = currentUid != null && (currentUid == ownerId || editors.contains(currentUid));

      final bool hasPermission = isLive || isInternalStaff || isAuthorizedCreator;

      if (!hasPermission) {
        setState(() {
          _isAccessDenied = true;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isAccessDenied = false;
        _resolvedType = fanzineData['type'] ?? 'fanzine';
        _fanzineTitle = fanzineData['title'] ?? 'Untitled';

        bool newTwoPagePref = fanzineData['twoPage'] ?? true;
        bool newHasCover = fanzineData['hasCover'] ?? true;
        bool prefChanged = !_isLoading && (_twoPagePreference != newTwoPagePref || _hasCover != newHasCover);

        if (_isLoading || prefChanged) {
          _twoPagePreference = newTwoPagePref;
          _hasCover = newHasCover;

          bool isDesktop = MediaQuery.of(context).size.width > 900;

          if (_isLoading && _targetIndex > 0) {
            // Keep deep-link state
          } else {
            if (_twoPagePreference) {
              if (_isEditingMode && isDesktop) {
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
          }
        }
      });
    });

    _pagesSubscription?.cancel();
    _pagesSubscription = FirebaseFirestore.instance
        .collection('fanzines')
        .doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final docs = snapshot.docs.map((d) {
        final data = d.data();
        data['__id'] = d.id;
        return data;
      }).toList();

      setState(() {
        _pages = docs;
        if (_targetIndex > _pages.length) _targetIndex = _pages.length;
        _isLoading = false;
      });
    });
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
            _twoPagePreference = false;
          });
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
    setState(() {
      _headerMode = HeaderMode.login;
    });
  }

  void _onAuthSuccess() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    setState(() {
      _headerMode = HeaderMode.fanzine;
    });
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

    if (_isEditingMode && _resolvedFanzineId != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: _resolvedType == 'calendar'
                ? CalendarEditorWidget(folioId: _resolvedFanzineId!)
                : (_resolvedType == 'folio' || _resolvedType == 'article')
                ? FanzineMakerWidget(fanzineId: _resolvedFanzineId!)
                : FanzineCuratorWidget(fanzineId: _resolvedFanzineId!),
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isAccessDenied) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: Center(
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
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth > 900;

            if (!isDesktop) {
              if (!_showList) {
                return FanzineGridRenderer(
                  pages: _pages,
                  headerWidget: _isEditingMode
                      ? GestureDetector(
                    onTap: () {
                      setState(() {
                        _showList = true;
                        _targetIndex = 0;
                      });
                    },
                    child: AbsorbPointer(
                      child: _buildHeader(isStickerOnly: true),
                    ),
                  )
                      : _buildHeader(isStickerOnly: false),
                  scrollController: ScrollController(),
                  viewService: _viewService,
                  hasCover: _hasCover,
                  onPageTap: _handlePageTap,
                );
              } else {
                return FanzineLayout(
                  viewMode: FanzineViewMode.single,
                  pages: _pages,
                  fanzineId: _resolvedFanzineId ?? '',
                  fanzineType: _resolvedType,
                  headerWidget: _buildHeader(),
                  gridScrollController: ScrollController(),
                  listScrollController: _mobileListScrollController,
                  initialIndex: _targetIndex,
                  viewService: _viewService,
                  isEditingMode: _isEditingMode,
                  activeGlobalPanel: _activeGlobalPanel,
                  onTogglePanel: _handlePanelToggle,
                  onSwitchToSingle: (idx) { setState(() => _targetIndex = idx); },
                  onOpenGrid: _handleCloseList,
                );
              }
            }

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
                          pages: _pages,
                          headerWidget: _buildHeader(isStickerOnly: _showList),
                          scrollController: _desktopGridScrollController ??= ScrollController(),
                          viewService: _viewService,
                          hasCover: _hasCover,
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
                                fanzineId: _resolvedFanzineId ?? '',
                                fanzineType: _resolvedType,
                                pages: _pages,
                                headerWidget: _buildHeader(isStickerOnly: false),
                                itemScrollController: _desktopListScrollController,
                                initialIndex: _targetIndex,
                                viewService: _viewService,
                                isEditingMode: _isEditingMode,
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
                          fanzineId: _resolvedFanzineId ?? '',
                          fanzineTitle: _fanzineTitle,
                          pages: _pages,
                          activePanel: _activeGlobalPanel!,
                          viewService: _viewService,
                          isEditingMode: _isEditingMode,
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
        ),
      ),
    );
  }
}