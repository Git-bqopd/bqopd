import 'package:flutter/material.dart';
import '../../config/reader_tools_config.dart';
import '../../models/reader_tool.dart';
import '../../components/dynamic_toolbar_button.dart';

class SocialMatrixTab extends StatefulWidget {
  const SocialMatrixTab({super.key});

  @override
  State<SocialMatrixTab> createState() => _SocialMatrixTabState();
}

class _SocialMatrixTabState extends State<SocialMatrixTab> {
  String _selectedRole = 'user'; // user, curator, moderator, admin

  List<String> _getConditionBullets(ReaderTool tool) {
    List<String> bullets = [];

    // 1. Role & Mode Restrictions
    if (tool.role == ToolRole.editor) {
      bullets.add("Restricted to Curators, Moderators, and Admins.");
      bullets.add("Only visible while in Edit Mode.");
    }

    // 2. User Toggles (Matching the logic in SettingsPanel & DynamicSocialToolbar)
    if (tool.role == ToolRole.public) {
      if (tool.id == 'Settings' || tool.id == 'Grid' || tool.id == 'Like') {
        bullets.add("Always visible (cannot be hidden by the user).");
      } else {
        bullets.add("Can be hidden by the user via toolbar settings.");
      }
    }

    // 3. Technical & Content Conditions
    switch (tool.condition) {
      case ToolCondition.requiresYouTube:
        bullets.add("Requires a YouTube ID attached by a maker/editor.");
        break;
      case ToolCondition.requiresGame:
        bullets.add("Requires the Terminal/Game flag enabled by a maker/editor.");
        break;
      case ToolCondition.requiresIndicia:
        bullets.add("Only visible on the issue's designated Indicia page.");
        break;
      case ToolCondition.requiresOcrPipeline:
        bullets.add("Only available for auto-processed archival works (requires OCR).");
        break;
      case ToolCondition.hideOnDesktopSplit:
        bullets.add("Hidden on desktop when grid and list are both visible.");
        bullets.add("Disabled if the folio is configured for single-column scrolling.");
        break;
      case ToolCondition.requiresTwoPage:
        bullets.add("Requires the folio to have Two-Page view enabled.");
        break;
      case ToolCondition.always:
      default:
        break;
    }

    return bullets;
  }

  @override
  Widget build(BuildContext context) {
    // Logic check: Is the curator area active for the selected role?
    // UPDATED: Curator column is now strictly tied to the curator selection
    final bool isCuratorActive = _selectedRole == 'curator';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        const Text(
          "SOCIAL BUTTONS MATRIX",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 2.0,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Visual registry of toolbar availability across program modules.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 40),

        Theme(
          data: Theme.of(context).copyWith(
            segmentedButtonTheme: SegmentedButtonThemeData(
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'user', label: Text('User'), icon: Icon(Icons.person, size: 20)),
              ButtonSegment(value: 'curator', label: Text('Curator'), icon: Icon(Icons.auto_fix_high, size: 20)),
              ButtonSegment(value: 'moderator', label: Text('Mod'), icon: Icon(Icons.security, size: 20)),
              ButtonSegment(value: 'admin', label: Text('Admin'), icon: Icon(Icons.star, size: 20)),
            ],
            selected: {_selectedRole},
            onSelectionChanged: (newSelection) {
              setState(() => _selectedRole = newSelection.first);
            },
          ),
        ),
        const SizedBox(height: 48),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 48,
                dataRowMinHeight: 110,
                dataRowMaxHeight: 150,
                headingRowHeight: 70,
                headingRowColor: WidgetStateProperty.all(Colors.grey[50]),
                columns: [
                  const DataColumn(label: Text('BUTTON', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1))),
                  const DataColumn(label: Text('DESCRIPTION & CONDITIONS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1))),
                  const DataColumn(label: Expanded(child: Text('Reader\n(Public)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)))),
                  const DataColumn(label: Expanded(child: Text('Maker\n(Manual)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)))),
                  DataColumn(
                      label: Expanded(
                          child: Opacity(
                              opacity: isCuratorActive ? 1.0 : 0.3,
                              child: const Text('Curator\n(Auto)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900))
                          )
                      )
                  ),
                ],
                rows: ReaderToolsConfig.tools.map((tool) {
                  return DataRow(cells: [
                    DataCell(Text(tool.label.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo))),
                    DataCell(SizedBox(
                      width: 250,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(tool.description, style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.black87)),
                          if (_getConditionBullets(tool).isNotEmpty) const SizedBox(height: 6),
                          ..._getConditionBullets(tool).map((bullet) =>
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("• ", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                    Expanded(
                                      child: Text(
                                          bullet,
                                          style: const TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic, height: 1.2)
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ),
                        ],
                      ),
                    )),
                    DataCell(Center(child: _buildPreview(tool, false, 'ingested'))),
                    DataCell(Center(child: _buildPreview(tool, true, 'folio'))),
                    // Mode 3: Curator (Column shuts off if role not selected)
                    DataCell(Center(
                        child: isCuratorActive
                            ? _buildPreview(tool, true, 'ingested')
                            : const Icon(Icons.lock_outline, color: Colors.black12, size: 16)
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildPreview(ReaderTool tool, bool isEditing, String type) {
    bool isVisible = ReaderToolsConfig.isToolVisibleInContext(
      tool: tool,
      userRole: _selectedRole,
      isEditingMode: isEditing,
      fanzineType: type,
      hasYoutube: true,
      isGame: true,
      isIndiciaPage: true,
      canOpenGrid: true,
      isTwoPage: true, // Mocked as true for matrix previews
    );

    if (!isVisible) {
      return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[50], shape: BoxShape.circle),
          child: const Icon(Icons.block, color: Colors.black12, size: 18)
      );
    }

    return DynamicToolbarButton(
      tool: tool,
      onPressed: () {},
      isActive: false,
    );
  }
}