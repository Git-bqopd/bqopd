import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/view_service.dart';
import '../utils/fanzine_single_view.dart';
import '../widgets/fanzine_widget.dart';

class FanzinePage extends StatefulWidget {
  final String? fanzineId;
  final String? shortCode;

  const FanzinePage({
    super.key,
    this.fanzineId,
    this.shortCode,
  });

  @override
  State<FanzinePage> createState() => _FanzinePageState();
}

class _FanzinePageState extends State<FanzinePage> {
  final ViewService _viewService = ViewService();

  bool _isSingleColumn = false;
  int _targetIndex = 0;
  List<Map<String, dynamic>> _pages = [];
  bool _isLoading = true;
  String? _resolvedFanzineId;
  String? _resolvedShortCode;

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
      await _loadPages(_resolvedFanzineId!);
      _processDeepLink(); // ADDED: Jump to specific page if fragment exists
      _updateUrlIfNeeded();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Parses the URL fragment (e.g. #p12) and sets the target scroll index.
  void _processDeepLink() {
    try {
      final router = GoRouter.of(context);
      final fragment = router.routerDelegate.currentConfiguration.uri.fragment;
      if (fragment.startsWith('p')) {
        final pageNum = int.tryParse(fragment.substring(1));
        if (pageNum != null && pageNum > 0) {
          setState(() {
            _targetIndex = pageNum; // 0 is header, so p1 is index 1
            _isSingleColumn = true; // Auto-expand if deep-linked to specific page
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadPages(String fanzineId) async {
    try {
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
          _pages = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
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

  void _recordViewForIndex(int index) {
    if (index > 0 && index <= _pages.length) {
      final pageData = _pages[index - 1];
      final imageId = pageData['imageId'];
      if (imageId != null) {
        _viewService.recordView(contentId: imageId, contentType: 'images');
      }
    }
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
              : _buildLayout(headerWidget),
        ),
      ),
    );
  }

  Widget _buildLayout(Widget headerWidget) {
    final int crossAxisCount = _isSingleColumn ? 1 : 2;
    final double childAspectRatio = _isSingleColumn ? 0.6 : 0.625;
    const double mainAxisSpacing = 30.0;
    const double crossAxisSpacing = 24.0;
    const double padding = 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final availableWidth = width - (padding * 2);
        final totalCrossAxisSpacing = (crossAxisCount - 1) * crossAxisSpacing;
        final itemWidth = (availableWidth - totalCrossAxisSpacing) / crossAxisCount;
        final itemHeight = itemWidth / childAspectRatio;
        final rowHeight = itemHeight + mainAxisSpacing;

        final rowIndex = (_targetIndex / crossAxisCount).floor();
        final initialOffset = rowIndex * rowHeight;

        _scrollController?.dispose();
        _scrollController = ScrollController(initialScrollOffset: initialOffset);

        if (_isSingleColumn) {
          return FanzineSingleView(
            fanzineId: _resolvedFanzineId ?? '',
            pages: _pages,
            headerWidget: headerWidget,
            scrollController: _scrollController!,
            viewService: _viewService,
            onOpenGrid: (currentIndex) {
              setState(() {
                _targetIndex = currentIndex;
                _isSingleColumn = false;
              });
            },
          );
        } else {
          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(padding),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.625,
              mainAxisSpacing: mainAxisSpacing,
              crossAxisSpacing: crossAxisSpacing,
            ),
            itemCount: _pages.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return headerWidget;
              final pageIndex = index - 1;
              final pageData = _pages[pageIndex];
              final imageUrl = pageData['imageUrl'] ?? '';

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _targetIndex = index;
                    _isSingleColumn = true;
                  });
                  _recordViewForIndex(index);
                },
                child: Container(
                  decoration: BoxDecoration(color: imageUrl.isEmpty ? Colors.grey[300] : Colors.white),
                  child: imageUrl.isNotEmpty ? Image.network(imageUrl, fit: BoxFit.contain) : null,
                ),
              );
            },
          );
        }
      },
    );
  }
}