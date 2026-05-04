import 'package:flutter/material.dart';

/// PageWrapper
/// - Centers content and limits its width (white margins on large screens)
/// - Optional built-in scrolling to prevent "RenderFlex overflowed" errors
class PageWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final bool scroll; // set true when content can exceed viewport height
  final Color? backgroundColor;

  const PageWrapper({
    super.key,
    required this.child,
    this.maxWidth = 1000, // tweak globally here (e.g., 900–1100)
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
    this.scroll = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );

    return Container(
      color: backgroundColor, // falls back to Scaffold background if null
      child: scroll ? SingleChildScrollView(child: content) : content,
    );
  }
}
