import 'package:bqopd_core/bqopd_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/user_provider.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  /// Internal bridge to map String Icon IDs from core to Flutter IconData.
  IconData _getIcon(String? id) {
    if (id == null) return Icons.help_outline;
    switch (id) {
      case 'article_outlined': return Icons.article_outlined;
      case 'article': return Icons.article;
      case 'chat_bubble_outline': return Icons.chat_bubble_outline;
      case 'chat_bubble': return Icons.chat_bubble;
      case 'favorite_border': return Icons.favorite_border;
      case 'favorite': return Icons.favorite;
      case 'settings_outlined': return Icons.settings_outlined;
      case 'settings': return Icons.settings;
      default: return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    final togglableTools = ReaderToolsConfig.tools
        .where((t) => t.id != 'Settings' && t.role == ToolRole.public)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("CUSTOMIZE TOOLBAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        ...togglableTools.map((tool) {
          final isVisible = userProvider.socialButtonVisibility[tool.id] ?? true;

          return SwitchListTile(
            title: Text(tool.label, style: const TextStyle(fontSize: 14)),
            value: isVisible,
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
              if (states.contains(WidgetState.selected)) {
                return Icon(_getIcon(tool.activeIcon ?? tool.defaultIcon));
              }
              return Icon(_getIcon(tool.defaultIcon));
            }),
            onChanged: (val) => userProvider.toggleSocialButtonVisibility(tool.id),
            dense: true,
          );
        }),
      ],
    );
  }
}