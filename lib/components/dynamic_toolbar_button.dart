import 'package:flutter/material.dart';
import '../models/reader_tool.dart';

class DynamicToolbarButton extends StatelessWidget {
  final ReaderTool tool;
  final VoidCallback onPressed;
  final bool isActive;
  final bool hasInteracted; // NEW: Indicates if the user left a comment, etc.
  final bool isDarkMode;
  final int? count;

  const DynamicToolbarButton({
    super.key,
    required this.tool,
    required this.onPressed,
    this.isActive = false,
    this.hasInteracted = false,
    this.isDarkMode = false,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if the icon should be bold/filled based on engagement
    bool showAsEngaged = (tool.id == 'Like' && isActive) || hasInteracted;

    IconData currentIcon = tool.defaultIcon;
    if (showAsEngaged && tool.activeIcon != null) {
      currentIcon = tool.activeIcon!;
    } else if (isDarkMode && tool.darkIcon != null) {
      currentIcon = tool.darkIcon!;
    }

    // 1. Determine the line/icon color (Grey by default, bold if active/engaged)
    Color iconAndBorderColor = (isActive || showAsEngaged) ? Colors.black : Colors.grey.shade600;
    if (isDarkMode) {
      iconAndBorderColor = (isActive || showAsEngaged) ? Colors.white : Colors.grey.shade400;
    }

    // Override for Like
    if (showAsEngaged && tool.id == 'Like') {
      iconAndBorderColor = Colors.redAccent;
    }

    // 2. Determine the background color (Fills in when the drawer is open)
    Color bgColor = Colors.transparent;
    if (isActive && tool.action == ToolAction.openBonusRow) {
      bgColor = isDarkMode ? Colors.white24 : Colors.black12; // Darkens background when open!
    } else if (showAsEngaged && tool.id == 'Like') {
      bgColor = Colors.redAccent.withValues(alpha: 0.1);
    }

    // 3. Determine the notification badge color
    Color badgeColor = Colors.grey.shade500;
    if (showAsEngaged && tool.id == 'Like') {
      badgeColor = Colors.redAccent;
    } else if (showAsEngaged) {
      badgeColor = isDarkMode ? Colors.white : Colors.black; // Bold badge for user comments
    } else if (count != null && count! > 0) {
      badgeColor = isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700; // Standard badge
    }

    Color badgeTextColor = (badgeColor == Colors.white || badgeColor == Colors.grey.shade400)
        ? Colors.black
        : Colors.white;

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
                    color: bgColor, // Dynamic filled background
                    shape: BoxShape.circle,
                    border: Border.all(color: iconAndBorderColor, width: 1.5),
                  ),
                  child: Icon(
                    currentIcon,
                    color: iconAndBorderColor,
                    size: 20,
                  ),
                ),
                // Render the count as a notification badge
                if (count != null && count! > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: badgeTextColor,
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
                fontWeight: (isActive || showAsEngaged) ? FontWeight.bold : FontWeight.normal,
                color: iconAndBorderColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}