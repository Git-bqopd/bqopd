import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../services/engagement_service.dart';
import '../services/user_provider.dart';
import '../services/event_service.dart';
import '../models/page_event.dart';
import '../widgets/event_editor_form.dart';
import '../widgets/event_reader_view.dart';
import 'social_action_button.dart';
import '../game/game_lobby.dart';
import '../widgets/login_widget.dart';

class SocialToolbar extends StatefulWidget {
  final String? imageId;
  final String? pageId;
  final String? fanzineId;
  final int? pageNumber;
  final bool isGame;
  final String? youtubeId;
  final bool isEditingMode;
  final VoidCallback? onToggleEditMode;
  final VoidCallback? onOpenGrid;
  final VoidCallback? onToggleComments;
  final VoidCallback? onToggleText;
  final VoidCallback? onToggleTags; // NEW: Callback for hashtag drawer
  final VoidCallback? onToggleViews;
  final VoidCallback? onToggleCredits;
  final VoidCallback? onToggleYouTube;
  final VoidCallback? onToggleOCR;
  final VoidCallback? onToggleEntities;
  final VoidCallback? onTogglePublisher;
  final VoidCallback? onToggleIndicia;

  final VoidCallback? onApprove;
  final VoidCallback? onFanzine;

  const SocialToolbar({
    super.key,
    this.imageId,
    this.pageId,
    this.fanzineId,
    this.pageNumber,
    this.isGame = false,
    this.youtubeId,
    this.isEditingMode = false,
    this.onToggleEditMode,
    this.onOpenGrid,
    this.onToggleComments,
    this.onToggleText,
    this.onToggleTags,
    this.onToggleViews,
    this.onToggleCredits,
    this.onToggleYouTube,
    this.onToggleOCR,
    this.onToggleEntities,
    this.onTogglePublisher,
    this.onToggleIndicia,
    this.onApprove,
    this.onFanzine,
  });

  @override
  State<SocialToolbar> createState() => _SocialToolbarState();
}

class _SocialToolbarState extends State<SocialToolbar> {
  final EngagementService _engagementService = EngagementService();
  final EventService _eventService = EventService();
  bool _isButtonsDrawerOpen = false;
  bool _isEventsExpanded = false;

  PageEvent? _editingEvent;
  bool _isAddingNewEvent = false;

  void _toggleButtonsDrawer() {
    setState(() {
      _isButtonsDrawerOpen = !_isButtonsDrawerOpen;
      if (_isButtonsDrawerOpen) {
        _isEventsExpanded = false;
        _resetEventState();
      }
    });
  }

  void _toggleEventsExpanded() {
    setState(() {
      _isEventsExpanded = !_isEventsExpanded;
      if (_isEventsExpanded) {
        _isButtonsDrawerOpen = false;
        _resetEventState();
      }
    });
  }

  void _resetEventState() {
    setState(() {
      _editingEvent = null;
      _isAddingNewEvent = false;
    });
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
            onTap: () {
              Navigator.pop(context);
              context.go('/register');
            },
            onLoginSuccess: () {
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  void _copyShareLink() async {
    if (widget.fanzineId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(widget.fanzineId)
          .get();
      final shortCode = doc.data()?['shortCode'] ?? widget.fanzineId;
      String url = "https://bqopd.com/$shortCode";
      if (widget.pageNumber != null) url += "?p=${widget.pageNumber}";
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Link copied: $url'),
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      debugPrint("Share error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final buttonVisibility = userProvider.socialButtonVisibility;
    final bool canShowTerminal =
        widget.isGame && (buttonVisibility['Terminal'] == true);
    final bool isEditor = userProvider.isEditor;

    return StreamBuilder<List<PageEvent>>(
      stream: _eventService.getEventsForPage(widget.pageId ?? ''),
      builder: (context, snapshot) {
        final events = snapshot.data ?? [];
        final hasEvents = events.isNotEmpty;
        final bool showEventsButton = isEditor || hasEvents;

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
                      SocialActionButton(
                          icon: Icons.menu_book, label: 'Open', onTap: widget.onOpenGrid),
                      const SizedBox(width: 16),
                    ],

                    if (widget.isEditingMode) ...[
                      if (buttonVisibility['Text'] == true) ...[
                        SocialActionButton(
                            icon: Icons.newspaper,
                            label: 'Text',
                            onTap: widget.onToggleText),
                        const SizedBox(width: 16),
                      ],
                      if (buttonVisibility['OCR'] == true) ...[
                        SocialActionButton(
                            icon: Icons.document_scanner,
                            label: 'OCR',
                            onTap: widget.onToggleOCR),
                        const SizedBox(width: 16),
                      ],
                      if (buttonVisibility['Entities'] == true) ...[
                        SocialActionButton(
                            icon: Icons.person_search,
                            label: 'Entities',
                            onTap: widget.onToggleEntities),
                        const SizedBox(width: 16),
                      ],
                      SocialActionButton(
                          icon: Icons.auto_awesome_motion,
                          label: 'Publisher',
                          onTap: widget.onTogglePublisher),
                      const SizedBox(width: 16),

                      if (buttonVisibility['Approve'] == true) ...[
                        SocialActionButton(
                            icon: Icons.verified,
                            label: 'Approve',
                            onTap: widget.onApprove),
                        const SizedBox(width: 16),
                      ],
                      if (buttonVisibility['Fanzine'] == true) ...[
                        SocialActionButton(
                            icon: Icons.auto_stories,
                            label: 'Fanzine',
                            onTap: widget.onFanzine),
                        const SizedBox(width: 16),
                      ],
                      if (buttonVisibility['Credits'] == true) ...[
                        SocialActionButton(
                            icon: Icons.people,
                            label: 'Credits',
                            onTap: widget.onToggleCredits),
                        const SizedBox(width: 16),
                      ],
                      if (buttonVisibility['Indicia'] == true && widget.onToggleIndicia != null) ...[
                        SocialActionButton(
                            icon: Icons.copyright,
                            label: 'Indicia',
                            onTap: widget.onToggleIndicia),
                        const SizedBox(width: 16),
                      ],
                      if (showEventsButton) ...[
                        SocialActionButton(
                            icon: Icons.event,
                            label: 'Events',
                            isActive: _isEventsExpanded,
                            onTap: _toggleEventsExpanded),
                        const SizedBox(width: 16),
                      ],
                      SocialActionButton(
                          icon: Icons.visibility,
                          label: 'Read',
                          onTap: widget.onToggleEditMode),
                      const SizedBox(width: 16),
                    ] else ...[
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
                                  count = (pageSnap.data!.data()
                                  as Map<String, dynamic>)['likeCount'] ??
                                      0;
                                }
                                return SocialActionButton(
                                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                                    label: 'Like',
                                    isActive: isLiked,
                                    count: count,
                                    onTap: () => _handleLike(isLiked));
                              },
                            );
                          },
                        )
                      else
                        const SocialActionButton(
                            icon: Icons.favorite_border, label: 'Like', count: 0),
                      const SizedBox(width: 16),

                      if (buttonVisibility['Comment'] == true) ...[
                        if (widget.imageId != null && widget.imageId!.isNotEmpty)
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('images')
                                .doc(widget.imageId)
                                .snapshots(),
                            builder: (context, imgSnap) {
                              int count = 0;
                              if (imgSnap.hasData && imgSnap.data!.exists) {
                                count = (imgSnap.data!.data()
                                as Map<String, dynamic>)['commentCount'] ??
                                    0;
                              }
                              return SocialActionButton(
                                  icon: Icons.comment,
                                  label: 'Comment',
                                  count: count,
                                  onTap: widget.onToggleComments);
                            },
                          )
                        else
                          SocialActionButton(
                              icon: Icons.comment,
                              label: 'Comment',
                              count: 0,
                              onTap: widget.onToggleComments),
                        const SizedBox(width: 16),
                      ],

                      if (buttonVisibility['Share'] == true) ...[
                        SocialActionButton(
                            icon: Icons.share, label: 'Share', onTap: _copyShareLink),
                        const SizedBox(width: 16),
                      ],

                      if (buttonVisibility['Views'] == true) ...[
                        if (widget.imageId != null && widget.imageId!.isNotEmpty)
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('images')
                                .doc(widget.imageId)
                                .snapshots(),
                            builder: (context, imgSnap) {
                              int count = 0;
                              if (imgSnap.hasData && imgSnap.data!.exists) {
                                final data =
                                imgSnap.data!.data() as Map<String, dynamic>;
                                count = (data['regListCount'] ?? 0) as int;
                              }
                              return SocialActionButton(
                                  icon: Icons.show_chart,
                                  label: 'Views',
                                  count: count,
                                  onTap: widget.onToggleViews);
                            },
                          )
                        else
                          const SocialActionButton(
                              icon: Icons.show_chart, label: 'Views', count: 0),
                        const SizedBox(width: 16),
                      ],

                      if (buttonVisibility['Text'] == true) ...[
                        SocialActionButton(
                            icon: Icons.newspaper,
                            label: 'Text',
                            onTap: widget.onToggleText),
                        const SizedBox(width: 16),
                      ],

                      if (buttonVisibility['Tags'] == true) ...[
                        SocialActionButton(
                            icon: Icons.tag,
                            label: 'Tags',
                            onTap: widget.onToggleTags),
                        const SizedBox(width: 16),
                      ],

                      if (buttonVisibility['Indicia'] == true && widget.onToggleIndicia != null) ...[
                        SocialActionButton(
                            icon: Icons.copyright,
                            label: 'Indicia',
                            onTap: widget.onToggleIndicia),
                        const SizedBox(width: 16),
                      ],

                      if (buttonVisibility['YouTube'] == true &&
                          widget.youtubeId != null &&
                          widget.youtubeId!.isNotEmpty) ...[
                        SocialActionButton(
                            icon: Icons.ondemand_video_outlined,
                            label: 'YouTube',
                            onTap: widget.onToggleYouTube),
                        const SizedBox(width: 16),
                      ],

                      if (showEventsButton) ...[
                        SocialActionButton(
                            icon: Icons.event,
                            label: 'Events',
                            isActive: _isEventsExpanded,
                            onTap: _toggleEventsExpanded),
                        const SizedBox(width: 16),
                      ],

                      if (buttonVisibility['Circulation'] == true) ...[
                        const SocialActionButton(icon: Icons.print, label: 'Circulation'),
                        const SizedBox(width: 16),
                      ],

                      if (canShowTerminal) ...[
                        SocialActionButton(
                            icon: Icons.terminal,
                            label: 'Terminal',
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (c) => const GameLobby()))),
                        const SizedBox(width: 16),
                      ],

                      if (isEditor && buttonVisibility['Edit'] != false) ...[
                        SocialActionButton(
                            icon: Icons.edit,
                            label: 'Edit',
                            onTap: widget.onToggleEditMode),
                        const SizedBox(width: 16),
                      ],
                    ],

                    SocialActionButton(
                        icon: Icons.apps,
                        label: 'Buttons',
                        isActive: _isButtonsDrawerOpen,
                        onTap: _toggleButtonsDrawer),
                  ],
                ),
              ),
            ),
            if (_isEventsExpanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 500),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isEditor && (_editingEvent != null || _isAddingNewEvent))
                          EventEditorForm(
                            pageId: widget.pageId ?? '',
                            existingEvent: _editingEvent,
                            onCancel: _resetEventState,
                            onSaveComplete: _resetEventState,
                          )
                        else if (isEditor)
                        // Editor view with management controls
                          Column(
                            children: [
                              Row(
                                children: [
                                  const Text('Page Events', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => setState(() => _isAddingNewEvent = true),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Another'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (events.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20.0),
                                  child: Text('No events listed for this page.'),
                                )
                              else
                                ...events.map((e) => _buildEditorEventCard(e)),
                            ],
                          )
                        else
                        // Reader-only view
                          EventReaderView(events: events),
                      ],
                    ),
                  ),
                ),
              ),
            if (_isButtonsDrawerOpen)
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(top: BorderSide(color: Colors.grey.shade200))),
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.isEditingMode) ...[
                          _DrawerItem(
                              label: 'Text',
                              icon: Icons.newspaper,
                              isSelected: buttonVisibility['Text'] ?? true,
                              onTap: () => userProvider.toggleSocialButton('Text')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'OCR',
                              icon: Icons.document_scanner,
                              isSelected: buttonVisibility['OCR'] ?? false,
                              onTap: () => userProvider.toggleSocialButton('OCR')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Entities',
                              icon: Icons.person_search,
                              isSelected: buttonVisibility['Entities'] ?? false,
                              onTap: () =>
                                  userProvider.toggleSocialButton('Entities')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Approve',
                              icon: Icons.verified,
                              isSelected: buttonVisibility['Approve'] ?? false,
                              onTap: () =>
                                  userProvider.toggleSocialButton('Approve')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Fanzine',
                              icon: Icons.auto_stories,
                              isSelected: buttonVisibility['Fanzine'] ?? false,
                              onTap: () =>
                                  userProvider.toggleSocialButton('Fanzine')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Credits',
                              icon: Icons.people,
                              isSelected: buttonVisibility['Credits'] ?? false,
                              onTap: () =>
                                  userProvider.toggleSocialButton('Credits')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Indicia',
                              icon: Icons.copyright,
                              isSelected: buttonVisibility['Indicia'] ?? true,
                              onTap: () =>
                                  userProvider.toggleSocialButton('Indicia')),
                        ] else ...[
                          _DrawerItem(
                              label: 'Comment',
                              icon: Icons.comment,
                              isSelected: buttonVisibility['Comment'] ?? true,
                              onTap: () =>
                                  userProvider.toggleSocialButton('Comment')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Share',
                              icon: Icons.share,
                              isSelected: buttonVisibility['Share'] ?? true,
                              onTap: () => userProvider.toggleSocialButton('Share')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Views',
                              icon: Icons.show_chart,
                              isSelected: buttonVisibility['Views'] ?? true,
                              onTap: () => userProvider.toggleSocialButton('Views')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Text',
                              icon: Icons.newspaper,
                              isSelected: buttonVisibility['Text'] ?? true,
                              onTap: () => userProvider.toggleSocialButton('Text')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Tags',
                              icon: Icons.tag,
                              isSelected: buttonVisibility['Tags'] ?? true,
                              onTap: () => userProvider.toggleSocialButton('Tags')),
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Indicia',
                              icon: Icons.copyright,
                              isSelected: buttonVisibility['Indicia'] ?? true,
                              onTap: () =>
                                  userProvider.toggleSocialButton('Indicia')),
                          if (widget.youtubeId != null &&
                              widget.youtubeId!.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            _DrawerItem(
                                label: 'Video',
                                icon: Icons.play_circle_outline,
                                isSelected: buttonVisibility['YouTube'] ?? true,
                                onTap: () =>
                                    userProvider.toggleSocialButton('YouTube')),
                          ],
                          const SizedBox(width: 10),
                          _DrawerItem(
                              label: 'Circulation',
                              icon: Icons.print,
                              isSelected: buttonVisibility['Circulation'] ?? true,
                              onTap: () =>
                                  userProvider.toggleSocialButton('Circulation')),
                          if (widget.isGame) ...[
                            const SizedBox(width: 10),
                            _DrawerItem(
                                label: 'Terminal',
                                icon: Icons.terminal,
                                isSelected: buttonVisibility['Terminal'] ?? false,
                                onTap: () =>
                                    userProvider.toggleSocialButton('Terminal')),
                          ],
                          if (isEditor) ...[
                            const SizedBox(width: 10),
                            Container(
                                height: 30, width: 2, color: Colors.grey.shade300),
                            const SizedBox(width: 10),
                            _DrawerItem(
                                label: 'Edit',
                                icon: Icons.edit,
                                isSelected: buttonVisibility['Edit'] ?? true,
                                onTap: () => userProvider.toggleSocialButton('Edit')),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEditorEventCard(PageEvent event) {
    final dateStr = event.startDate == event.endDate
        ? DateFormat('MMM dd, yyyy').format(event.startDate)
        : '${DateFormat('MMM dd').format(event.startDate)} - ${DateFormat('MMM dd, yyyy').format(event.endDate)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => setState(() => _editingEvent = event),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.eventName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(dateStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    if (event.venueName.isNotEmpty)
                      Text(event.venueName, style: TextStyle(color: Colors.grey.shade800, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.edit, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  const _DrawerItem(
      {required this.label,
        required this.icon,
        required this.isSelected,
        required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.black : Colors.grey.shade300;
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2)),
            child: Icon(icon, color: color, size: 18)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: isSelected ? Colors.black : Colors.grey)),
      ]),
    );
  }
}