import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/user_provider.dart';
import '../../config/reader_tools_config.dart';
import '../../models/reader_tool.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    // Grab all public tools so the user can toggle them on/off.
    // Excludes 'Settings', 'Grid' (Open), and 'Like' so they can never be hidden.
    final togglableTools = ReaderToolsConfig.tools
        .where((t) =>
    t.id != 'Settings' &&
        t.id != 'Grid' &&
        t.id != 'Like' &&
        t.role == ToolRole.public)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "CUSTOMIZE TOOLBAR",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        ...togglableTools.map((tool) {
          final isVisible = userProvider.socialButtonVisibility[tool.id] ?? true;

          final WidgetStateProperty<Icon?> thumbIcon =
          WidgetStateProperty.resolveWith<Icon?>(
                (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return Icon(tool.activeIcon ?? tool.defaultIcon);
              }
              return Icon(tool.defaultIcon);
            },
          );

          return SwitchListTile(
            title: Text(tool.label, style: const TextStyle(fontSize: 14)),
            value: isVisible,
            thumbIcon: thumbIcon,
            onChanged: (val) {
              userProvider.toggleSocialButtonVisibility(tool.id);
            },
            dense: true,
          );
        }),
      ],
    );
  }
}