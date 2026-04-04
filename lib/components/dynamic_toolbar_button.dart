import 'package:flutter/material.dart';
import '../models/reader_tool.dart';

class DynamicToolbarButton extends StatelessWidget {
  final ReaderTool tool;
  final VoidCallback onPressed;
  final bool isActive;
  final bool isDarkMode;

  const DynamicToolbarButton({
    super.key,
    required this.tool,
    required this.onPressed,
    this.isActive = false,
    this.isDarkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Determine the appropriate Icon to display
    IconData currentIcon = tool.defaultIcon;

    if (isActive && tool.activeIcon != null) {
      currentIcon = tool.activeIcon!;
    } else if (isDarkMode && tool.darkIcon != null) {
      currentIcon = tool.darkIcon!;
    }

    // 2. Determine background shading and icon color dynamically
    // In light mode, it uses a soft grey shade. In dark mode, a deep grey shade.
    final Color bgColor = isDarkMode ? const Color(0xFF333333) : const Color(0xFFF0F0F0);
    final Color baseIconColor = isDarkMode ? Colors.white : Colors.black87;

    // Highlight active icons (e.g., a solid red heart for 'Like' or the primary theme color)
    Color iconColor = baseIconColor;
    if (isActive) {
      iconColor = tool.id == 'Like' ? Colors.redAccent : Theme.of(context).primaryColor;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: tool.label, // Uses the label from the registry
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
            ),
            child: Icon(
              currentIcon,
              color: iconColor,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}