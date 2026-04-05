import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/view_service.dart';

/// A single row in the Fanzine Grid (Gallery) view representing a two-page spread.
/// Designed to look like an 11 x 8.5 sheet of paper.
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
      child: Center(
        child: AspectRatio(
          aspectRatio: paperRatio,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2), // Very slight rounding like paper
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            // The "Sheet" Padding
            padding: const EdgeInsets.all(24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LEFT PAGE
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12.0), // Padding between images
                    child: Center(
                      child: leftWidget ??
                          (leftPageData != null
                              ? _SpreadPageItem(
                            index: leftIndex!,
                            pageData: leftPageData!,
                            onTap: () => onPageTap(leftIndex!),
                            viewService: viewService,
                            fanzineId: fanzineId,
                            fanzineTitle: fanzineTitle,
                          )
                              : const SizedBox.shrink()),
                    ),
                  ),
                ),

                // RIGHT PAGE
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12.0), // Padding between images
                    child: Center(
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
                ),
              ],
            ),
          ),
        ),
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
    final storagePath = widget.pageData['storagePath'];
    final imageUrl = widget.pageData['imageUrl'];

    if (storagePath != null && storagePath.toString().isNotEmpty) {
      try {
        final url = await FirebaseStorage.instance.ref(storagePath).getDownloadURL();
        if (mounted) setState(() { _resolvedImageUrl = url; _isLoading = false; });
        return;
      } catch (_) {}
    }

    if (mounted) setState(() { _resolvedImageUrl = imageUrl; _isLoading = false; });
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
        aspectRatio: 0.625, // Forces the 5:8 ratio for the image itself
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[50], // Very subtle background for image area
            border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.5),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty)
              ? Image.network(
            _resolvedImageUrl!,
            fit: BoxFit.contain,
            errorBuilder: (c, e, s) => Center(
              child: Text("Page $pageNum", style: const TextStyle(color: Colors.grey)),
            ),
          )
              : Center(child: Text("Page $pageNum")),
        ),
      ),
    );
  }
}