import 'package:flutter/material.dart';

/// A unified wrapper for Reader Panels.
///
/// If [isInline] is true, it renders as a flat container inserted between list items (Mobile/List view).
/// If [isInline] is false, it renders as an expanded column with a distinct title header (Desktop Split view).
class PanelContainer extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isInline;
  final Color inlineColor;

  const PanelContainer({
    super.key,
    required this.title,
    required this.child,
    this.isInline = true,
    this.inlineColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    if (isInline) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: inlineColor,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: child,
      );
    }

    // Desktop Sidebar Layout
    // Important: mainAxisSize must be min so it doesn't cause infinite height errors in ListViews
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ],
    );
  }
}