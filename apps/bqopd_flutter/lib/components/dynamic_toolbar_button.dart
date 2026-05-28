import 'package:flutter/material.dart';
import 'package:bqopd_core/bqopd_core.dart';

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

  /// Maps string identifiers from the core package to Flutter IconData.
  IconData _getIcon(String? id) {
    if (id == null) return Icons.help_outline;
    switch (id) {
      case 'article_outlined': return Icons.article_outlined;
      case 'article': return Icons.article;
      case 'chat_bubble_outline': return Icons.chat_bubble_outline;
      case 'chat_bubble': return Icons.chat_bubble;
      case 'favorite_border': return Icons.favorite_border;
      case 'favorite': return Icons.favorite;
      case 'share_outlined': return Icons.share_outlined;
      case 'grid_view': return Icons.grid_view;
      case 'menu_book': return Icons.menu_book;
      case 'settings_outlined': return Icons.settings_outlined;
      case 'settings': return Icons.settings;
      case 'play_circle_outline': return Icons.play_circle_outline;
      case 'play_circle_filled': return Icons.play_circle_filled;
      case 'tag': return Icons.tag;
      case 'info_outline': return Icons.info_outline;
      case 'info': return Icons.info;
      case 'outdoor_grill': return Icons.outdoor_grill;
      case 'edit_document': return Icons.edit_document;
      case 'add_link': return Icons.add_link;
      case 'link_outlined': return Icons.link_outlined;
      case 'link': return Icons.link;
      case 'bar_chart_outlined': return Icons.bar_chart_outlined;
      case 'bar_chart': return Icons.bar_chart;
      case 'manage_accounts_outlined': return Icons.manage_accounts_outlined;
      case 'manage_accounts': return Icons.manage_accounts;
      case 'terminal': return Icons.terminal; // Map string tool icon
      default: return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Resolve which string ID to use based on state
    String iconId = tool.defaultIcon;
    if (isActive && tool.activeIcon != null) {
      iconId = tool.activeIcon!;
    } else if (isDarkMode && tool.darkIcon != null) {
      iconId = tool.darkIcon!;
    }

    // Convert string ID to Flutter IconData
    final IconData currentIcon = _getIcon(iconId);

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