import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/view_service.dart';
import '../widgets/fanzine_widget.dart';
import '../widgets/fanzine_layout.dart';

class FanzineReaderPage extends StatefulWidget {
  final String? fanzineId;
  final String? shortCode;

  const FanzineReaderPage({
    super.key,
    this.fanzineId,
    this.shortCode,
  });

  @override
  State<FanzineReaderPage> createState() => _FanzineReaderPageState();
}

class _FanzineReaderPageState extends State<FanzineReaderPage> {
  final ViewService _viewService = ViewService();

  bool _isLoading = true;
  String? _resolvedFanzineId;
  String? _resolvedShortCode;
  List<Map<String, dynamic>> _pages = [];

  bool _supportsGrid = true;
  FanzineViewMode _viewMode = FanzineViewMode.grid;
  int _targetIndex = 0; // 0 = Header, 1 = Page 1

  ScrollController? _scrollController;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    String? targetShortCode = widget.shortCode;
    String? targetId = widget.fanzineId;

    // Resolve Identity
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
      await _fetchFanzineData(_resolvedFanzineId!);
      _processDeepLink();
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
      final bool twoPage = fanzineData['twoPage'] ?? true;

      final snapshot = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(fanzineId)
          .collection('pages')
          .get();

      final docs = snapshot.docs.map((d) {
        final data = d.data();
        data['__id'] = d.id;
        return data;
      }).toList();

      docs.sort((a, b) {
        int aNum = (a['pageNumber'] ?? a['index'] ?? 0) as int;
        int bNum = (b['pageNumber'] ?? b['index'] ?? 0) as int;
        return aNum.compareTo(bNum);
      });

      if (mounted) {
        setState(() {
          _supportsGrid = twoPage;
          _viewMode = twoPage ? FanzineViewMode.grid : FanzineViewMode.single;
          _pages = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processDeepLink() {
    try {
      final router = GoRouter.of(context);
      final fragment = router.routerDelegate.currentConfiguration.uri.fragment;
      if (fragment.startsWith('p')) {
        final pageNum = int.tryParse(fragment.substring(1));
        if (pageNum != null && pageNum > 0) {
          setState(() {
            _targetIndex = pageNum;
            _viewMode = FanzineViewMode.single;
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
          if (!currentLoc.contains(_resolvedShortCode!)) {
            context.go('/$_resolvedShortCode');
          }
        } catch (_) {}
      });
    }
  }

  void _switchToSingle(int index) {
    setState(() {
      _targetIndex = index;
      _viewMode = FanzineViewMode.single;
    });
  }

  void _switchToGrid(int index) {
    if (!_supportsGrid) return;
    setState(() {
      _targetIndex = index;
      _viewMode = FanzineViewMode.grid;
    });
  }

  ScrollController _initScrollControllerForLayout(BoxConstraints constraints) {
    _scrollController?.dispose();

    double initialOffset = 0;

    // Constants from Renderers
    const double padding = 8.0;
    const double mainAxisSpacing = 30.0;
    const double crossAxisSpacing = 24.0;
    const double childAspectRatio = 0.625; // 5:8

    final width = constraints.maxWidth;
    final availableWidth = width - (padding * 2);

    int crossAxisCount = 1;
    if (_viewMode == FanzineViewMode.grid) {
      crossAxisCount = 2;
    } else {
      crossAxisCount = 1; // List Mode matches Grid with 1 column (Legacy logic)
    }

    final totalCrossAxisSpacing = (crossAxisCount - 1) * crossAxisSpacing;
    final itemWidth = (availableWidth - totalCrossAxisSpacing) / crossAxisCount;
    final itemHeight = itemWidth / childAspectRatio;
    final rowHeight = itemHeight + mainAxisSpacing;

    final rowIndex = (_targetIndex / crossAxisCount).floor();
    initialOffset = rowIndex * rowHeight;

    _scrollController = ScrollController(initialScrollOffset: initialOffset);
    return _scrollController!;
  }

  @override
  Widget build(BuildContext context) {
    final headerWidget = FanzineWidget(fanzineShortCode: _resolvedShortCode);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
            builder: (context, constraints) {
              return FanzineLayout(
                viewMode: _viewMode,
                pages: _pages,
                fanzineId: _resolvedFanzineId ?? '',
                headerWidget: headerWidget,
                scrollController: _initScrollControllerForLayout(constraints),
                viewService: _viewService,
                onSwitchToSingle: _switchToSingle,
                onSwitchToGrid: _supportsGrid ? _switchToGrid : null,
              );
            },
          ),
        ),
      ),
    );
  }
}