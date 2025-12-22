import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/view_service.dart';
import '../services/user_provider.dart';
import 'social_action_button.dart';
import '../game/game_lobby.dart'; // Import Game Lobby

class SocialToolbar extends StatefulWidget {
  final String? imageId; // For view counting and future features
  final VoidCallback? onOpenGrid; // Specific to Fanzine View
  final VoidCallback? onToggleComments; // External handler for comments (optional)
  final VoidCallback? onToggleText; // External handler for text (optional)
  final bool isSingleColumn; // To adjust layout if needed

  const SocialToolbar({
    super.key,
    this.imageId,
    this.onOpenGrid,
    this.onToggleComments,
    this.onToggleText,
    this.isSingleColumn = false,
  });

  @override
  State<SocialToolbar> createState() => _SocialToolbarState();
}

class _SocialToolbarState extends State<SocialToolbar> {
  final ViewService _viewService = ViewService();

  // State for the "Buttons" Drawer
  bool _isButtonsDrawerOpen = false;

  void _toggleButtonsDrawer() {
    setState(() {
      _isButtonsDrawerOpen = !_isButtonsDrawerOpen;
    });
  }

  void _openGameLobby() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GameLobby()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // CONSUME GLOBAL PREFERENCES
    final userProvider = Provider.of<UserProvider>(context);
    final buttonVisibility = userProvider.socialButtonVisibility;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. The Main Row of Icons
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Open -> Switch back to Grid (Only if callback provided)
                if (widget.onOpenGrid != null) ...[
                  SocialActionButton(
                    icon: Icons.menu_book,
                    label: 'Open',
                    onTap: widget.onOpenGrid,
                  ),
                  const SizedBox(width: 16),
                ],

                // Like (Always visible for now)
                const SocialActionButton(icon: Icons.favorite_border, label: 'Like', count: 0),
                const SizedBox(width: 16),

                // Comment
                if (buttonVisibility['Comment'] == true) ...[
                  SocialActionButton(
                    icon: Icons.comment,
                    label: 'Comment',
                    count: 0,
                    onTap: widget.onToggleComments,
                  ),
                  const SizedBox(width: 16),
                ],

                // Share
                if (buttonVisibility['Share'] == true) ...[
                  const SocialActionButton(icon: Icons.share, label: 'Share', count: 0),
                  const SizedBox(width: 16),
                ],

                // Views
                if (buttonVisibility['Views'] == true) ...[
                  SocialActionButton(
                    icon: Icons.show_chart,
                    label: 'Views',
                    countFuture: widget.imageId != null
                        ? _viewService.getViewCount(contentId: widget.imageId!, contentType: 'images')
                        : null,
                  ),
                  const SizedBox(width: 16),
                ],

                // Text
                if (buttonVisibility['Text'] == true) ...[
                  SocialActionButton(
                    icon: Icons.newspaper,
                    label: 'Text',
                    onTap: widget.onToggleText,
                  ),
                  const SizedBox(width: 16),
                ],

                // Circulation
                if (buttonVisibility['Circulation'] == true) ...[
                  const SocialActionButton(icon: Icons.print, label: 'Circulation'),
                  const SizedBox(width: 16),
                ],

                // Terminal, CA (Game Launch Button)
                if (buttonVisibility['Terminal'] == true) ...[
                  SocialActionButton(
                    icon: Icons.terminal,
                    label: 'Terminal',
                    onTap: _openGameLobby,
                  ),
                  const SizedBox(width: 16),
                ],

                // --- EDITOR TOOLS (Conditionally visible in main row) ---
                if (buttonVisibility['Approve'] == true) ...[
                  const SocialActionButton(
                    icon: Icons.check_circle_outline,
                    label: 'Approve',
                  ),
                  const SizedBox(width: 16),
                ],

                if (buttonVisibility['Fanzine'] == true) ...[
                  const SocialActionButton(
                    icon: Icons.auto_stories,
                    label: 'Fanzine',
                  ),
                  const SizedBox(width: 16),
                ],

                // "Buttons" (The Standard Drawer Toggle)
                SocialActionButton(
                  icon: Icons.apps,
                  label: 'Buttons',
                  isActive: _isButtonsDrawerOpen,
                  onTap: _toggleButtonsDrawer,
                ),
              ],
            ),
          ),
        ),

        // 2. The Drawer (Unified Buttons Box)
        if (_isButtonsDrawerOpen)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ROW 1: Standard Social Buttons
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DrawerItem(
                        label: 'Comment',
                        icon: Icons.comment,
                        isSelected: buttonVisibility['Comment']!,
                        onTap: () => userProvider.toggleSocialButton('Comment'),
                      ),
                      const SizedBox(width: 10),
                      _DrawerItem(
                        label: 'Share',
                        icon: Icons.share,
                        isSelected: buttonVisibility['Share']!,
                        onTap: () => userProvider.toggleSocialButton('Share'),
                      ),
                      const SizedBox(width: 10),
                      _DrawerItem(
                        label: 'Views',
                        icon: Icons.show_chart,
                        isSelected: buttonVisibility['Views']!,
                        onTap: () => userProvider.toggleSocialButton('Views'),
                      ),
                      const SizedBox(width: 10),
                      _DrawerItem(
                        label: 'Text',
                        icon: Icons.newspaper,
                        isSelected: buttonVisibility['Text']!,
                        onTap: () => userProvider.toggleSocialButton('Text'),
                      ),
                      const SizedBox(width: 10),
                      _DrawerItem(
                        label: 'Circulation',
                        icon: Icons.print,
                        isSelected: buttonVisibility['Circulation']!,
                        onTap: () => userProvider.toggleSocialButton('Circulation'),
                      ),
                      const SizedBox(width: 10),
                      _DrawerItem(
                        label: 'Terminal, CA',
                        icon: Icons.terminal,
                        isSelected: buttonVisibility['Terminal'] ?? false,
                        onTap: () => userProvider.toggleSocialButton('Terminal'),
                      ),
                    ],
                  ),
                ),

                // SECTION 2: Editor's Desk (Only for Editors)
                if (userProvider.isEditor) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(height: 1, thickness: 0.5),
                  ),
                  const Text(
                    "Editor's Desk",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DrawerItem(
                        label: 'Approve',
                        icon: Icons.check_circle_outline,
                        isSelected: buttonVisibility['Approve'] ?? false,
                        onTap: () => userProvider.toggleSocialButton('Approve'),
                      ),
                      const SizedBox(width: 20),
                      _DrawerItem(
                        label: 'Fanzine',
                        icon: Icons.auto_stories,
                        isSelected: buttonVisibility['Fanzine'] ?? false,
                        onTap: () => userProvider.toggleSocialButton('Fanzine'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Styling: Black = Selected (Visible in toolbar), Grey = Unselected (Hidden)
    final color = isSelected ? Colors.black : Colors.grey.shade300;
    final textColor = isSelected ? Colors.black : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: textColor)),
        ],
      ),
    );
  }
}