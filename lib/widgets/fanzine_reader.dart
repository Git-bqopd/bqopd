import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../services/view_service.dart';
import '../utils/fanzine_single_view.dart';

class FanzineReader extends StatefulWidget {
  final String fanzineId;
  final Widget headerWidget;

  const FanzineReader({
    super.key,
    required this.fanzineId,
    required this.headerWidget,
  });

  @override
  State<FanzineReader> createState() => _FanzineReaderState();
}

class _FanzineReaderState extends State<FanzineReader> {
  final ViewService _viewService = ViewService();

  bool _isSingleColumn = false;
  int _targetIndex = 0;
  List<Map<String, dynamic>> _pages = [];
  bool _isLoading = true;

  ScrollController? _scrollController;

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  Future<void> _loadPages() async {
    if (widget.fanzineId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch Fanzine Doc to get Shortcode and potentially update URL
      final fanzineDoc = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(widget.fanzineId)
          .get();

      if (fanzineDoc.exists) {
        final shortCode = fanzineDoc.data()?['shortCode'] as String?;
        if (shortCode != null && shortCode.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              // Attempt to update the browser URL if it doesn't match
              try {
                final router = GoRouter.of(context);
                final currentLoc = router.routerDelegate.currentConfiguration.uri.toString();
                // Simple check to avoid loops: if we aren't already at this shortcode
                if (!currentLoc.contains(shortCode)) {
                  // router.replaceNamed('shortlink', pathParameters: {'code': shortCode});
                }
              } catch (e) {
                // Not in a router context or router not ready
              }
            }
          });
        }
      }

      // 2. Fetch Pages
      final snapshot = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(widget.fanzineId)
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
      print("Error loading fanzine: $e");
      if (mounted) setState(() => _isLoading = false);
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // 1. Determine Layout Params for calculation
    final int crossAxisCount = _isSingleColumn ? 1 : 2;
    // IMPORTANT: These must match what is used in FanzineSingleView and below for consistency
    final double childAspectRatio = _isSingleColumn ? 0.6 : 0.625;
    const double mainAxisSpacing = 30.0;
    const double crossAxisSpacing = 24.0; // only matters for grid
    const double padding = 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 2. Calculate Initial Offset
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
            pages: _pages,
            headerWidget: widget.headerWidget,
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
          // Inline Grid Builder (2 Columns)
          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(padding),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.625, // 5/8
              mainAxisSpacing: mainAxisSpacing,
              crossAxisSpacing: crossAxisSpacing,
            ),
            itemCount: _pages.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return widget.headerWidget;

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
                  decoration: BoxDecoration(
                    color: imageUrl.isEmpty ? Colors.grey[300] : Colors.white,
                  ),
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.contain)
                      : null,
                ),
              );
            },
          );
        }
      },
    );
  }
}