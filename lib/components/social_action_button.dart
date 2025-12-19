import 'package:flutter/material.dart';

class SocialActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<int>? countFuture;
  final int? count;
  final VoidCallback? onTap;
  final bool isActive; // For toggled states like "Liked"
  final bool showBorder; // New style option for "Follow" style buttons

  const SocialActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.countFuture,
    this.count,
    this.onTap,
    this.isActive = false,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = isActive ? theme.primaryColor : Colors.grey[700];
    final labelColor = isActive ? theme.primaryColor : Colors.grey[600];

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: baseColor,
              size: 20,
            ),
            if (countFuture != null) ...[
              const SizedBox(width: 4),
              FutureBuilder<int>(
                future: countFuture,
                builder: (context, snapshot) => Text(
                  snapshot.hasData ? '${snapshot.data}' : '...',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: baseColor,
                  ),
                ),
              ),
            ] else if (count != null) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: baseColor,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: labelColor,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );

    if (showBorder) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: baseColor ?? Colors.black),
          borderRadius: BorderRadius.circular(4), // Slight radius or 0 for sharp
        ),
        child: content,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: content,
      ),
    );
  }
}