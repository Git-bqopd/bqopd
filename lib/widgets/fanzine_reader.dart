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

  // State
  bool _isSingleView = false;
  List<Map<String, dynamic>> _pages = [];
  bool _isLoading = true;

  // Global toggle state for boxes
  bool _areCommentBoxesOpen = false;
  bool _areTextBoxesOpen = false;
  bool _areAppsBoxesOpen = false;

  // Visible Social Buttons State (True = Visible)
  // "Open" and "Like" are always visible, so we don't need to track them here necessarily,
  // but for consistency in the "Apps" box, we track the toggleable ones.
  Map<String, bool> _buttonVisibility = {
    'Comment': true,
    'Share': true,
    'Views': true,
    'Text': true,
    'Circulation': true,
  };

  // Scroll Keys
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    if (widget.fanzineId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

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
  }

  GlobalKey _getKey(int index) {
    if (!_itemKeys.containsKey(index)) {
      _itemKeys[index] = GlobalKey();
    }
    return _itemKeys[index]!;
  }

  // --- NAVIGATION LOGIC ---

  void _scrollToIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[index];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.0,
        );
      }
    });
  }

  void _switchToSingleView(int index) {
    setState(() {
      _isSingleView = true;
    });
    _scrollToIndex(index);
  }

  void _switchToGridView(int index) {
    setState(() {
      _isSingleView = false;
    });
    _scrollToIndex(index);
  }

  // --- TOGGLE LOGIC ---

  void _toggleAllCommentBoxes() {
    setState(() {
      _areCommentBoxesOpen = !_areCommentBoxesOpen;
      if (_areCommentBoxesOpen) {
        _areTextBoxesOpen = false;
        _areAppsBoxesOpen = false;
      }
    });
  }

  void _toggleAllTextBoxes() {
    setState(() {
      _areTextBoxesOpen = !_areTextBoxesOpen;
      if (_areTextBoxesOpen) {
        _areCommentBoxesOpen = false;
        _areAppsBoxesOpen = false;
      }
    });
  }

  void _toggleAllAppsBoxes() {
    setState(() {
      _areAppsBoxesOpen = !_areAppsBoxesOpen;
      if (_areAppsBoxesOpen) {
        _areCommentBoxesOpen = false;
        _areTextBoxesOpen = false;
      }
    });
  }

  void _toggleButtonVisibility(String key) {
    setState(() {
      _buttonVisibility[key] = !(_buttonVisibility[key] ?? true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return _isSingleView ? _buildSinglePageView() : _buildTwoPageSpread();
  }

  // --- MODE A: GRID VIEW ---
  Widget _buildTwoPageSpread() {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 5 / 8,
        mainAxisSpacing: 30.0,
        crossAxisSpacing: 24.0,
      ),
      itemCount: _pages.length + 1,
      itemBuilder: (context, index) {
        final key = _getKey(index);

        if (index == 0) {
          return Container(key: key, child: widget.headerWidget);
        }

        final pageIndex = index - 1;
        final pageData = _pages[pageIndex];
        final imageUrl = pageData['imageUrl'] ?? '';

        return GestureDetector(
          onTap: () => _switchToSingleView(index),
          child: Container(
            key: key,
            color: imageUrl.isEmpty ? Colors.grey[300] : null,
            child: imageUrl.isNotEmpty
                ? Image.network(imageUrl, fit: BoxFit.contain)
                : null,
          ),
        );
      },
    );
  }

  // --- MODE B: SINGLE PAGE VIEW ---
  Widget _buildSinglePageView() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      itemCount: _pages.length + 1,
      separatorBuilder: (c, i) => const SizedBox(height: 32),
      itemBuilder: (context, index) {
        final key = _getKey(index);

        if (index == 0) {
          return AspectRatio(
            key: key,
            aspectRatio: 5 / 8,
            child: widget.headerWidget,
          );
        }

        final pageIndex = index - 1;
        final pageData = _pages[pageIndex];
        final imageUrl = pageData['imageUrl'] ?? '';
        final imageId = pageData['imageId'];

        if (imageId != null) {
          _viewService.recordView(contentId: imageId, contentType: 'images');
        }

        return Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            imageUrl.isEmpty
                ? Container(height: 300, color: Colors.grey[300])
                : Image.network(imageUrl, fit: BoxFit.contain),

            Padding(
              padding: const EdgeInsets.all(8.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 1. Open (Always Visible)
                    _SocialButton(
                        icon: Icons.menu_book,
                        label: 'Open',
                        onTap: () {
                          _switchToGridView(index);
                        }
                    ),
                    const SizedBox(width: 16),

                    // 2. Like (Always Visible)
                    _SocialButton(icon: Icons.favorite_border, label: 'Like', count: 0),
                    const SizedBox(width: 16),

                    // 3. Comment (Toggleable)
                    if (_buttonVisibility['Comment'] == true) ...[
                      _SocialButton(
                        icon: Icons.comment,
                        label: 'Comment',
                        count: 0,
                        onTap: _toggleAllCommentBoxes,
                      ),
                      const SizedBox(width: 16),
                    ],

                    // 4. Share (Toggleable)
                    if (_buttonVisibility['Share'] == true) ...[
                      _SocialButton(icon: Icons.share, label: 'Share', count: 0),
                      const SizedBox(width: 16),
                    ],

                    // 5. Views (Toggleable)
                    if (_buttonVisibility['Views'] == true) ...[
                      _SocialButton(
                          icon: Icons.show_chart,
                          label: 'Views',
                          countFuture: imageId != null ? _viewService.getViewCount(contentId: imageId, contentType: 'images') : null
                      ),
                      const SizedBox(width: 16),
                    ],

                    // 6. Text (Toggleable)
                    if (_buttonVisibility['Text'] == true) ...[
                      _SocialButton(
                        icon: Icons.newspaper,
                        label: 'Text',
                        onTap: _toggleAllTextBoxes,
                      ),
                      const SizedBox(width: 16),
                    ],

                    // 7. Circulation (Toggleable)
                    if (_buttonVisibility['Circulation'] == true) ...[
                      _SocialButton(icon: Icons.print, label: 'Circulation'),
                      const SizedBox(width: 16),
                    ],

                    // 8. Buttons / Apps (Always Visible, Always Last)
                    _SocialButton(
                      icon: Icons.apps,
                      label: 'Buttons',
                      onTap: _toggleAllAppsBoxes,
                    ),
                  ],
                ),
              ),
            ),

            // --- BOXES ---

            if (_areCommentBoxesOpen)
              _buildExpandableBox(
                context,
                title: 'Write a comment:',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const TextField(
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Type here...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => print("Save comment tapped for page $index"),
                      style: ElevatedButton.styleFrom(
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),

            if (_areTextBoxesOpen)
              _buildExpandableBox(
                context,
                title: 'Text from this page:',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const TextField(
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Type here...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => print("Save text tapped for page $index"),
                      style: ElevatedButton.styleFrom(
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),

            if (_areAppsBoxesOpen)
              _buildExpandableBox(
                context,
                title: null, // No title for Apps box
                child: Center(
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      _AppSelectionButton(
                        label: 'Comment',
                        icon: Icons.comment,
                        isSelected: _buttonVisibility['Comment']!,
                        onTap: () => _toggleButtonVisibility('Comment'),
                      ),
                      _AppSelectionButton(
                        label: 'Share',
                        icon: Icons.share,
                        isSelected: _buttonVisibility['Share']!,
                        onTap: () => _toggleButtonVisibility('Share'),
                      ),
                      _AppSelectionButton(
                        label: 'Views',
                        icon: Icons.show_chart,
                        isSelected: _buttonVisibility['Views']!,
                        onTap: () => _toggleButtonVisibility('Views'),
                      ),
                      _AppSelectionButton(
                        label: 'Text',
                        icon: Icons.newspaper,
                        isSelected: _buttonVisibility['Text']!,
                        onTap: () => _toggleButtonVisibility('Text'),
                      ),
                      _AppSelectionButton(
                        label: 'Circulation',
                        icon: Icons.print,
                        isSelected: _buttonVisibility['Circulation']!,
                        onTap: () => _toggleButtonVisibility('Circulation'),
                      ),
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

  Widget _buildExpandableBox(BuildContext context, {String? title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
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

class _AppSelectionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AppSelectionButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.black : Colors.grey.shade300; // Changed to Black
    final textColor = isSelected ? Colors.black : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: textColor)),
        ],
      ),
    );
  }
}