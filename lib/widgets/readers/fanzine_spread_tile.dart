import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/view_service.dart';

/// A single row in the Fanzine Grid (Gallery) view representing a two-page spread.
/// Uses a Stack for the header row to layer a larger Manila Envelope over standard paper.
class FanzineSpreadTile extends StatelessWidget {
  final Widget? leftWidget;
  final Map<String, dynamic>? leftPageData;
  final Map<String, dynamic>? rightPageData;
  final int? leftIndex;
  final int? rightIndex;
  final Function(int) onPageTap;
  final ViewService viewService;
  final String fanzineId;
  final String fanzineTitle;

  const FanzineSpreadTile({
    super.key,
    this.leftWidget,
    this.leftPageData,
    this.rightPageData,
    this.leftIndex,
    this.rightIndex,
    required this.onPageTap,
    required this.viewService,
    required this.fanzineId,
    required this.fanzineTitle,
  });

  @override
  Widget build(BuildContext context) {
    // Standard US Letter Landscape ratio
    const double paperRatio = 11 / 8.5;
    final bool isHeaderRow = leftWidget != null;

    // --- BASE LAYER: Standard White Paper Spread ---
    // This defines the "physical" grid line that all pages follow.
    Widget baseSpread = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: AspectRatio(
        aspectRatio: paperRatio,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.all(24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Page (Hidden by Envelope in header row)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: leftPageData != null
                      ? _SpreadPageItem(
                    index: leftIndex!,
                    pageData: leftPageData!,
                    onTap: () => onPageTap(leftIndex!),
                    viewService: viewService,
                    fanzineId: fanzineId,
                    fanzineTitle: fanzineTitle,
                  )
                      : const SizedBox.shrink(),
                ),
              ),
              // Right Page
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: rightPageData != null
                      ? _SpreadPageItem(
                    index: rightIndex!,
                    pageData: rightPageData!,
                    onTap: () => onPageTap(rightIndex!),
                    viewService: viewService,
                    fanzineId: fanzineId,
                    fanzineTitle: fanzineTitle,
                  )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!isHeaderRow) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(child: baseSpread),
      );
    }

    // --- OVERLAY LAYER: The Manila Envelope ---
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24.0),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none, // Allow envelope to bleed
        children: [
          // 1. The standard paper spread (centered)
          baseSpread,

          // 2. The Manila Envelope sitting on top
          Positioned(
            left: 0, // PINNED TO ABSOLUTE LEFT OF THE SCREEN
            top: 0,
            bottom: 0,
            child: LayoutBuilder(builder: (context, constraints) {
              // We use a Row with a Spacer to maintain alignment relative to the spread center
              return Center(
                child: AspectRatio(
                  aspectRatio: paperRatio,
                  child: Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(builder: (context, innerConstraints) {
                          // The envelope is positioned to overflow exactly to the left edge
                          // while covering the left half of the spread.
                          return OverflowBox(
                            maxWidth: innerConstraints.maxWidth + 16, // Bleed to absolute screen edge
                            maxHeight: innerConstraints.maxHeight + 32, // Physical scale increase (top/bottom)
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 16), // Create space to show center paper fold
                              child: AspectRatio(
                                aspectRatio: 0.625, // Fixed 5:8 ratio (The correct "Size")
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF1B255), // Manila
                                    borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(12),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 15,
                                        offset: Offset(4, 8),
                                      )
                                    ],
                                  ),
                                  child: leftWidget,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const Spacer(), // Right half is clear so paper peeks through
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _SpreadPageItem extends StatefulWidget {
  final int index;
  final Map<String, dynamic> pageData;
  final VoidCallback onTap;
  final ViewService viewService;
  final String fanzineId;
  final String fanzineTitle;

  const _SpreadPageItem({
    required this.index,
    required this.pageData,
    required this.onTap,
    required this.viewService,
    required this.fanzineId,
    required this.fanzineTitle,
  });

  @override
  State<_SpreadPageItem> createState() => _SpreadPageItemState();
}

class _SpreadPageItemState extends State<_SpreadPageItem> {
  String? _resolvedImageUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _recordView();
    _resolveUrl();
  }

  Future<void> _resolveUrl() async {
    final storagePath =
        widget.pageData['thumbnailStoragePath'] ?? widget.pageData['storagePath'];
    final imageUrl =
        widget.pageData['thumbnailUrl'] ?? widget.pageData['imageUrl'];

    if (storagePath != null && storagePath.toString().isNotEmpty) {
      try {
        final url =
        await FirebaseStorage.instance.ref(storagePath).getDownloadURL();
        if (mounted) {
          setState(() {
            _resolvedImageUrl = url;
            _isLoading = false;
          });
        }
        return;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _resolvedImageUrl = imageUrl;
        _isLoading = false;
      });
    }
  }

  void _recordView() {
    final String imageId = widget.pageData['imageId'] ?? '';
    final String pageId = widget.pageData['__id'] ?? '';

    if (imageId.isNotEmpty) {
      widget.viewService.recordView(
        imageId: imageId,
        pageId: pageId,
        fanzineId: widget.fanzineId,
        fanzineTitle: widget.fanzineTitle,
        type: ViewType.grid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageNum = widget.pageData['pageNumber'] ?? widget.index;

    return GestureDetector(
      onTap: widget.onTap,
      child: AspectRatio(
        aspectRatio: 0.625,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1),
            border:
            Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.5),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty)
              ? Image.network(
            _resolvedImageUrl!,
            fit: BoxFit.contain,
            errorBuilder: (c, e, s) => Center(
              child: Text("Page $pageNum",
                  style: const TextStyle(color: Colors.grey)),
            ),
          )
              : Center(child: Text("Page $pageNum")),
        ),
      ),
    );
  }
}