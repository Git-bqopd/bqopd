import 'package:flutter/material.dart';
import '../services/view_service.dart';

class FanzineSingleView extends StatefulWidget {
  final List<Map<String, dynamic>> pages;
  final Widget headerWidget;
  final ScrollController scrollController;
  final Function(int) onOpenGrid;
  final ViewService viewService;

  const FanzineSingleView({
    super.key,
    required this.pages,
    required this.headerWidget,
    required this.scrollController,
    required this.onOpenGrid,
    required this.viewService,
  });

  @override
  State<FanzineSingleView> createState() => _FanzineSingleViewState();
}

class _FanzineSingleViewState extends State<FanzineSingleView> {
  // Local state for expandable boxes
  bool _areCommentBoxesOpen = false;
  bool _areTextBoxesOpen = false;
  bool _areAppsBoxesOpen = false;

  Map<String, bool> _buttonVisibility = {
    'Comment': true,
    'Share': true,
    'Views': true,
    'Text': true,
    'Circulation': true,
  };

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
    // 1 Column Grid Layout
    const int crossAxisCount = 1;
    const double childAspectRatio = 0.6;
    const double mainAxisSpacing = 30.0;
    const double crossAxisSpacing = 0.0;
    const double padding = 8.0;

    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(padding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      ),
      itemCount: widget.pages.length + 1, // +1 for Header
      itemBuilder: (context, index) {
        if (index == 0) {
          return widget.headerWidget;
        }

        final pageIndex = index - 1;
        final pageData = widget.pages[pageIndex];
        return _buildSingleColumnItem(index, pageData);
      },
    );
  }

  Widget _buildSingleColumnItem(int index, Map<String, dynamic> pageData) {
    final imageUrl = pageData['imageUrl'] ?? '';
    final imageId = pageData['imageId'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Image
        Expanded(
          child: Container(
            color: imageUrl.isEmpty ? Colors.grey[300] : null,
            child: imageUrl.isNotEmpty
                ? Image.network(imageUrl, fit: BoxFit.contain)
                : null,
          ),
        ),

        // 2. Controls
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Open -> Switch back to Grid
                _SocialButton(
                    icon: Icons.menu_book,
                    label: 'Open',
                    onTap: () => widget.onOpenGrid(index)
                ),
                const SizedBox(width: 16),

                // Like
                const _SocialButton(icon: Icons.favorite_border, label: 'Like', count: 0),
                const SizedBox(width: 16),

                // Comment
                if (_buttonVisibility['Comment'] == true) ...[
                  _SocialButton(icon: Icons.comment, label: 'Comment', count: 0, onTap: _toggleAllCommentBoxes),
                  const SizedBox(width: 16),
                ],

                // Share
                if (_buttonVisibility['Share'] == true) ...[
                  const _SocialButton(icon: Icons.share, label: 'Share', count: 0),
                  const SizedBox(width: 16),
                ],

                // Views
                if (_buttonVisibility['Views'] == true) ...[
                  _SocialButton(
                      icon: Icons.show_chart,
                      label: 'Views',
                      countFuture: imageId != null ? widget.viewService.getViewCount(contentId: imageId, contentType: 'images') : null
                  ),
                  const SizedBox(width: 16),
                ],

                // Text
                if (_buttonVisibility['Text'] == true) ...[
                  _SocialButton(icon: Icons.newspaper, label: 'Text', onTap: _toggleAllTextBoxes),
                  const SizedBox(width: 16),
                ],

                // Circulation
                if (_buttonVisibility['Circulation'] == true) ...[
                  const _SocialButton(icon: Icons.print, label: 'Circulation'),
                  const SizedBox(width: 16),
                ],

                // Buttons (Apps)
                _SocialButton(icon: Icons.apps, label: 'Buttons', onTap: _toggleAllAppsBoxes),
              ],
            ),
          ),
        ),

        // 3. Expandable Boxes
        if (_areCommentBoxesOpen) _buildExpandableBox(title: 'Write a comment:', child: const Text("Comment input...")),
        if (_areTextBoxesOpen) _buildExpandableBox(title: 'Text:', child: const Text("Page text...")),
        if (_areAppsBoxesOpen) _buildAppsBox(),
      ],
    );
  }

  Widget _buildExpandableBox({String? title, required Widget child}) {
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildAppsBox() {
    return Container(
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AppSelectionButton(label: 'Comment', icon: Icons.comment, isSelected: _buttonVisibility['Comment']!, onTap: () => _toggleButtonVisibility('Comment')),
              const SizedBox(width: 10),
              _AppSelectionButton(label: 'Share', icon: Icons.share, isSelected: _buttonVisibility['Share']!, onTap: () => _toggleButtonVisibility('Share')),
              const SizedBox(width: 10),
              _AppSelectionButton(label: 'Views', icon: Icons.show_chart, isSelected: _buttonVisibility['Views']!, onTap: () => _toggleButtonVisibility('Views')),
              const SizedBox(width: 10),
              _AppSelectionButton(label: 'Text', icon: Icons.newspaper, isSelected: _buttonVisibility['Text']!, onTap: () => _toggleButtonVisibility('Text')),
              const SizedBox(width: 10),
              _AppSelectionButton(label: 'Circulation', icon: Icons.print, isSelected: _buttonVisibility['Circulation']!, onTap: () => _toggleButtonVisibility('Circulation')),
            ],
          ),
        ),
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
        padding: const EdgeInsets.all(4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.grey[700], size: 20),
                if (countFuture != null) ...[
                  const SizedBox(width: 4),
                  FutureBuilder<int>(
                    future: countFuture,
                    builder: (context, snapshot) => Text(snapshot.hasData ? '${snapshot.data}' : '...', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                  ),
                ] else if (count != null) ...[
                  const SizedBox(width: 4),
                  Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
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
    final color = isSelected ? Colors.black : Colors.grey.shade300;
    final textColor = isSelected ? Colors.black : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: textColor)),
        ],
      ),
    );
  }
}