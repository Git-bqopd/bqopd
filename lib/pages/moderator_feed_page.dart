import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // Import for launching URL
import '../services/user_provider.dart';
import '../widgets/page_wrapper.dart';
import '../widgets/hashtag_bar.dart';
import '../components/dynamic_social_toolbar.dart';
import '../models/reader_tool.dart';
import '../models/panel_context.dart';
import '../widgets/reader_panels/panel_factory.dart';
import '../widgets/reader_panels/panel_container.dart';
import '../services/engagement_service.dart';
import '../services/view_service.dart';

class ModeratorFeedPage extends StatefulWidget {
  const ModeratorFeedPage({super.key});

  @override
  State<ModeratorFeedPage> createState() => _ModeratorFeedPageState();
}

class _ModeratorFeedPageState extends State<ModeratorFeedPage> {

  @override
  Widget build(BuildContext context) {
    // Security Gate: Ensure only Editors/Mods can see this
    final userProvider = Provider.of<UserProvider>(context);
    if (!userProvider.isEditor) {
      return const Scaffold(body: Center(child: Text("Restricted Area. Authorized Personnel Only.")));
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("Moderator Feed (Unpublished)"),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: PageWrapper(
        maxWidth: 800,
        scroll: false,
        child: StreamBuilder<QuerySnapshot>(
          // Query: pending status, ordered by newest.
          stream: FirebaseFirestore.instance
              .collection('images')
              .where('status', isEqualTo: 'pending')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            // --- ERROR HANDLING START ---
            if (snapshot.hasError) {
              final errorMsg = snapshot.error.toString();
              // Check for Firestore Index requirement
              if (errorMsg.contains('failed-precondition') ||
                  errorMsg.contains('requires an index')) {
                // Try to extract URL
                final urlRegex =
                RegExp(r'https://console\.firebase\.google\.com[^\s]+');
                final match = urlRegex.firstMatch(errorMsg);
                final indexUrl = match?.group(0);

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Database Index Required",
                            style: TextStyle(
                                color: Colors.red, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                            "To view the feed sorted by date, a Firestore index is needed.",
                            textAlign: TextAlign.center),
                        if (indexUrl != null) ...[
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => launchUrl(Uri.parse(indexUrl)),
                            child: const Text("Create Index"),
                          )
                        ] else
                          SelectableText(errorMsg,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              }
              return Center(child: SelectableText("Error: $errorMsg"));
            }
            // --- ERROR HANDLING END ---

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Center(child: Text("Queue clear. Good job!"));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (c, i) => const SizedBox(height: 32),
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                return _ModeratorCard(docId: docs[index].id, data: data);
              },
            );
          },
        ),
      ),
    );
  }
}

class _ModeratorCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const _ModeratorCard({required this.docId, required this.data});

  @override
  State<_ModeratorCard> createState() => _ModeratorCardState();
}

class _ModeratorCardState extends State<_ModeratorCard> {
  final TextEditingController _commentController = TextEditingController();
  final EngagementService _engagementService = EngagementService();
  final ViewService _viewService = ViewService();
  final ValueNotifier<double> _fontSizeNotifier = ValueNotifier(16.0);
  BonusRowType? _activePanel;

  void _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _commentController.clear();

    await _engagementService.addComment(
      imageId: widget.docId,
      fanzineId: 'moderation_queue',
      fanzineTitle: 'Moderator Feed',
      text: text,
      displayName: userProvider.userProfile?['displayName'],
      username: userProvider.userProfile?['username'],
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _fontSizeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.data['fileUrl'] as String?;
    final tags = widget.data['tags'] as Map<String, dynamic>? ?? {};
    final uploaderId = widget.data['uploaderId'] as String? ?? 'unknown';

    // Check approval status via hashtags
    final bool isApproved = tags.containsKey('approved') && (tags['approved'] as List).isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
        border: isApproved
            ? Border.all(color: Colors.green.withValues(alpha: 0.5), width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner for unapproved
          if (!isApproved)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              color: Colors.amber[100],
              child: const Text(
                "NOT YET APPROVED",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                textAlign: TextAlign.center,
              ),
            ),

          // Image
          if (imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                height: 400, // Fixed height for consistency in feed
                errorBuilder: (c, e, s) => const SizedBox(height: 200, child: Center(child: Icon(Icons.broken_image))),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Uploader Info
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('Users').doc(uploaderId).get(),
                  builder: (context, snap) {
                    final userData = snap.data?.data() as Map<String, dynamic>?;
                    final username = userData?['username'] ?? uploaderId;
                    return Text("Uploaded by @$username", style: const TextStyle(color: Colors.grey, fontSize: 12));
                  },
                ),
                const SizedBox(height: 8),

                // Hashtag Bar
                HashtagBar(imageId: widget.docId, tags: tags),

                const SizedBox(height: 12),
                const Divider(height: 1),

                // Social Toolbar (for Like/Comment toggling)
                DynamicSocialToolbar(
                  imageId: widget.docId,
                  isGame: false,
                  isEditingMode: false,
                  activeBonusRow: _activePanel,
                  onToggleBonusRow: (rowType) {
                    setState(() {
                      _activePanel = _activePanel == rowType ? null : rowType;
                    });
                  },
                ),

                // Inline Bonus Row Section
                if (_activePanel != null) ...[
                  const Divider(height: 1),
                  PanelContainer(
                    title: '',
                    isInline: true,
                    inlineColor: PanelFactory.getInlineColor(_activePanel!),
                    child: PanelFactory.buildPanelContent(
                        PanelContext(
                          type: _activePanel!,
                          imageId: widget.docId,
                          actualText: widget.data['text'] ?? widget.data['text_raw'] ?? '',
                          isEditingMode: false,
                          viewService: _viewService,
                          engagementService: _engagementService,
                          commentController: _commentController,
                          onSubmitComment: _submitComment,
                          fontSizeNotifier: _fontSizeNotifier,
                        )
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}