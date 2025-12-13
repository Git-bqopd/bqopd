import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/view_service.dart';

class FanzineReader extends StatefulWidget {
  final String fanzineId;
  final Widget headerWidget; // The cover/info widget

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

  // State: false = Two Page Spread (Grid), true = Single Page View (List)
  bool _isSingleView = false;

  // Data
  List<Map<String, dynamic>> _pages = [];
  bool _isLoading = true;

  // Controllers
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    // If empty ID (no fanzine found), just stop loading
    if (widget.fanzineId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 1. Fetch pages for this fanzine
    final snapshot = await FirebaseFirestore.instance
        .collection('fanzines')
        .doc(widget.fanzineId)
        .collection('pages')
        .get();

    final docs = snapshot.docs.map((d) {
      final data = d.data();
      data['__id'] = d.id; // Keep reference to page ID if needed
      return data;
    }).toList();

    // 2. Sort by pageNumber
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
  }

  void _switchToSingleView(int initialIndex) {
    setState(() {
      _isSingleView = true;
    });
    // Slight delay to allow ListView to build before scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Ideally we'd calculate offset based on (index * estimatedHeight).
        // For now, it just switches mode.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // Main layout based on state - No FAB anymore
    return _isSingleView ? _buildSinglePageView() : _buildTwoPageSpread();
  }

  // --- MODE A: TWO PAGE SPREAD (Grid) ---
  // Does NOT count views.
  Widget _buildTwoPageSpread() {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65, // Adjust for fanzine aspect ratio
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
      ),
      // +1 for the Header Widget
      itemCount: _pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return widget.headerWidget;

        final pageIndex = index - 1;
        final pageData = _pages[pageIndex];
        final imageUrl = pageData['imageUrl'] ?? '';

        return GestureDetector(
          onTap: () => _switchToSingleView(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4), // Square edges as requested (small radius looks nicer but keeps square feel)
            child: imageUrl.isEmpty
                ? Container(color: Colors.grey[300])
                : Image.network(imageUrl, fit: BoxFit.cover),
          ),
        );
      },
    );
  }

  // --- MODE B: SINGLE PAGE VIEW (List) ---
  // COUNTS views as they render.
  Widget _buildSinglePageView() {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      itemCount: _pages.length + 1,
      separatorBuilder: (c, i) => const SizedBox(height: 32), // Space between pages
      itemBuilder: (context, index) {
        if (index == 0) return widget.headerWidget;

        final pageIndex = index - 1;
        final pageData = _pages[pageIndex];
        final imageUrl = pageData['imageUrl'] ?? '';
        final imageId = pageData['imageId']; // The MASTER ID

        // --- VIEW COUNTING LOGIC ---
        // This builder is called when the item is about to be rendered on screen.
        if (imageId != null) {
          _viewService.recordView(contentId: imageId, contentType: 'images');
        }
        // ---------------------------

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The Page Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8), // Square edges
              child: imageUrl.isEmpty
                  ? Container(height: 300, color: Colors.grey[300])
                  : Image.network(imageUrl, fit: BoxFit.contain),
            ),

            // Social / Interaction Bar
            Padding(
              padding: const EdgeInsets.all(8.0),
              // FittedBox ensures it shrinks to fit if too narrow, instead of overflowing
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, // Center the buttons
                  children: [
                    _SocialButton(
                        icon: Icons.menu_book, // Replaced two_pager
                        label: 'Open',
                        onTap: () {
                          setState(() {
                            _isSingleView = false;
                          });
                        }
                    ),
                    const SizedBox(width: 16),
                    _SocialButton(icon: Icons.favorite_border, label: 'Like', count: 0),
                    const SizedBox(width: 16),
                    _SocialButton(icon: Icons.comment, label: 'Comment', count: 0),
                    const SizedBox(width: 16),
                    _SocialButton(icon: Icons.share, label: 'Share', count: 0),
                    const SizedBox(width: 16),
                    _SocialButton(
                        icon: Icons.show_chart,
                        label: 'Views',
                        countFuture: imageId != null ? _viewService.getViewCount(contentId: imageId, contentType: 'images') : null
                    ),
                    const SizedBox(width: 16),
                    _SocialButton(icon: Icons.newspaper, label: 'Text'),
                    const SizedBox(width: 16),
                    _SocialButton(icon: Icons.print, label: 'Circulation'),
                  ],
                ),
              ),
            ),
            const Divider(),
          ],
        );
      },
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<int>? countFuture;
  final int? count;
  final VoidCallback? onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    this.countFuture,
    this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.grey[700]),
                if (countFuture != null) ...[
                  const SizedBox(width: 4),
                  FutureBuilder<int>(
                    future: countFuture,
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.hasData ? '${snapshot.data}' : '...',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                      );
                    },
                  ),
                ] else if (count != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}