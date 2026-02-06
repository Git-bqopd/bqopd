import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../services/view_service.dart';
import '../services/engagement_service.dart';
import '../services/user_provider.dart';
import 'social_action_button.dart';
import '../game/game_lobby.dart';
import '../widgets/login_widget.dart';

class SocialToolbar extends StatefulWidget {
  final String? imageId;
  final String? pageId;
  final String? fanzineId;
  final int? pageNumber;
  final bool isGame;
  final VoidCallback? onOpenGrid;
  final VoidCallback? onToggleComments;
  final VoidCallback? onToggleText;
  final VoidCallback? onToggleViews;

  const SocialToolbar({
    super.key,
    this.imageId,
    this.pageId,
    this.fanzineId,
    this.pageNumber,
    this.isGame = false,
    this.onOpenGrid,
    this.onToggleComments,
    this.onToggleText,
    this.onToggleViews,
  });

  @override
  State<SocialToolbar> createState() => _SocialToolbarState();
}

class _SocialToolbarState extends State<SocialToolbar> {
  final EngagementService _engagementService = EngagementService();
  bool _isButtonsDrawerOpen = false;

  void _toggleButtonsDrawer() {
    setState(() { _isButtonsDrawerOpen = !_isButtonsDrawerOpen; });
  }

  void _handleLike(bool isLiked) {
    if (widget.fanzineId == null || widget.pageId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      _showLoginPrompt();
      return;
    }
    _engagementService.toggleLike(
      fanzineId: widget.fanzineId!,
      pageId: widget.pageId!,
      isCurrentlyLiked: isLiked,
    );
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          child: LoginWidget(
            onTap: () { Navigator.pop(context); context.go('/register'); },
            onLoginSuccess: () { Navigator.pop(context); },
          ),
        ),
      ),
    );
  }

  void _copyShareLink() async {
    if (widget.fanzineId == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).get();
      final shortCode = doc.data()?['shortCode'] ?? widget.fanzineId;
      String url = "https://bqopd.com/$shortCode";
      if (widget.pageNumber != null) url += "#p${widget.pageNumber}";
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link copied: $url'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) { debugPrint("Share error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final buttonVisibility = userProvider.socialButtonVisibility;
    final bool canShowTerminal = widget.isGame && (buttonVisibility['Terminal'] == true);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.onOpenGrid != null) ...[
                  SocialActionButton(icon: Icons.menu_book, label: 'Open', onTap: widget.onOpenGrid),
                  const SizedBox(width: 16),
                ],

                if (widget.pageId != null && widget.fanzineId != null)
                  StreamBuilder<bool>(
                    stream: _engagementService.isLikedStream(widget.pageId!),
                    builder: (context, likedSnap) {
                      final bool isLiked = likedSnap.data ?? false;
                      return StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('fanzines')
                            .doc(widget.fanzineId)
                            .collection('pages')
                            .doc(widget.pageId)
                            .snapshots(),
                        builder: (context, pageSnap) {
                          int count = 0;
                          if (pageSnap.hasData && pageSnap.data!.exists) {
                            count = (pageSnap.data!.data() as Map<String, dynamic>)['likeCount'] ?? 0;
                          }
                          return SocialActionButton(
                            icon: isLiked ? Icons.favorite : Icons.favorite_border,
                            label: 'Like',
                            isActive: isLiked,
                            count: count,
                            onTap: () => _handleLike(isLiked),
                          );
                        },
                      );
                    },
                  )
                else
                  const SocialActionButton(icon: Icons.favorite_border, label: 'Like', count: 0),

                const SizedBox(width: 16),

                if (buttonVisibility['Comment'] == true) ...[
                  if (widget.imageId != null && widget.imageId!.isNotEmpty)
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('images').doc(widget.imageId).snapshots(),
                      builder: (context, imgSnap) {
                        int count = 0;
                        if (imgSnap.hasData && imgSnap.data!.exists) {
                          count = (imgSnap.data!.data() as Map<String, dynamic>)['commentCount'] ?? 0;
                        }
                        return SocialActionButton(
                          icon: Icons.comment,
                          label: 'Comment',
                          count: count,
                          onTap: widget.onToggleComments,
                        );
                      },
                    )
                  else
                    SocialActionButton(icon: Icons.comment, label: 'Comment', count: 0, onTap: widget.onToggleComments),
                  const SizedBox(width: 16),
                ],

                if (buttonVisibility['Share'] == true) ...[
                  SocialActionButton(icon: Icons.share, label: 'Share', onTap: _copyShareLink),
                  const SizedBox(width: 16),
                ],

                // --- UPDATED VIEW COUNTER: SHOWS ONLY 'regListCount' ---
                if (buttonVisibility['Views'] == true) ...[
                  if (widget.imageId != null && widget.imageId!.isNotEmpty)
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('images').doc(widget.imageId).snapshots(),
                      builder: (context, imgSnap) {
                        int count = 0;
                        if (imgSnap.hasData && imgSnap.data!.exists) {
                          final data = imgSnap.data!.data() as Map<String, dynamic>;
                          // DISPLAY RULE: Only Registered Users in List View
                          count = (data['regListCount'] ?? 0) as int;
                        }
                        return SocialActionButton(
                          icon: Icons.show_chart,
                          label: 'Views',
                          count: count,
                          onTap: widget.onToggleViews,
                        );
                      },
                    )
                  else
                    const SocialActionButton(icon: Icons.show_chart, label: 'Views', count: 0),
                  const SizedBox(width: 16),
                ],

                if (buttonVisibility['Text'] == true) ...[
                  SocialActionButton(icon: Icons.newspaper, label: 'Text', onTap: widget.onToggleText),
                  const SizedBox(width: 16),
                ],

                if (buttonVisibility['Circulation'] == true) ...[
                  const SocialActionButton(icon: Icons.print, label: 'Circulation'),
                  const SizedBox(width: 16),
                ],

                if (canShowTerminal) ...[
                  SocialActionButton(icon: Icons.terminal, label: 'Terminal', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const GameLobby()))),
                  const SizedBox(width: 16),
                ],

                SocialActionButton(icon: Icons.apps, label: 'Buttons', isActive: _isButtonsDrawerOpen, onTap: _toggleButtonsDrawer),
              ],
            ),
          ),
        ),

        if (_isButtonsDrawerOpen)
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade200))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DrawerItem(label: 'Comment', icon: Icons.comment, isSelected: buttonVisibility['Comment']!, onTap: () => userProvider.toggleSocialButton('Comment')),
                  const SizedBox(width: 10),
                  _DrawerItem(label: 'Share', icon: Icons.share, isSelected: buttonVisibility['Share']!, onTap: () => userProvider.toggleSocialButton('Share')),
                  const SizedBox(width: 10),
                  _DrawerItem(label: 'Views', icon: Icons.show_chart, isSelected: buttonVisibility['Views']!, onTap: () => userProvider.toggleSocialButton('Views')),
                  const SizedBox(width: 10),
                  _DrawerItem(label: 'Text', icon: Icons.newspaper, isSelected: buttonVisibility['Text']!, onTap: () => userProvider.toggleSocialButton('Text')),
                  const SizedBox(width: 10),
                  _DrawerItem(label: 'Circulation', icon: Icons.print, isSelected: buttonVisibility['Circulation']!, onTap: () => userProvider.toggleSocialButton('Circulation')),
                  if (widget.isGame) ...[
                    const SizedBox(width: 10),
                    _DrawerItem(label: 'Terminal', icon: Icons.terminal, isSelected: buttonVisibility['Terminal'] ?? false, onTap: () => userProvider.toggleSocialButton('Terminal')),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final String label; final IconData icon; final bool isSelected; final VoidCallback onTap;
  const _DrawerItem({required this.label, required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.black : Colors.grey.shade300;
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: color, width: 2)), child: Icon(icon, color: color, size: 18)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: isSelected ? Colors.black : Colors.grey)),
      ]),
    );
  }
}