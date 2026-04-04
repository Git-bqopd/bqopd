import 'package:flutter/material.dart';
import '../models/reader_tool.dart';

class DynamicToolbarButton extends StatelessWidget {
  final ReaderTool tool;
  final VoidCallback onPressed;
  final bool isActive;
  final bool isDarkMode;
  final int? count;

  const DynamicToolbarButton({
    super.key,
    required this.tool,
    required this.onPressed,
    this.isActive = false,
    this.isDarkMode = false,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    IconData currentIcon = tool.defaultIcon;

    if (isActive && tool.activeIcon != null) {
      currentIcon = tool.activeIcon!;
    } else if (isDarkMode && tool.darkIcon != null) {
      currentIcon = tool.darkIcon!;
    }

    // Match the _DrawerItem style from the old SocialToolbar
    Color color = Colors.black;
    if (isDarkMode) {
      color = Colors.white;
    }

    // Special override for the "Like" button to be red when active
    if (isActive && tool.id == 'Like') {
      color = Colors.redAccent;
    }

    // ONLY apply the background tint if the button is active/selected!
    Color bgColor = isActive ? color.withValues(alpha: 0.1) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10), // Padding inside circle
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2), // Outlined circle
                  ),
                  child: Icon(
                    currentIcon,
                    color: color,
                    size: 20,
                  ),
                ),
                // Render the count as a notification badge
                if (count != null && count! > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isActive ? color : Colors.grey.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tool.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}