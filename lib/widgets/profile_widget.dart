import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/user_provider.dart';
import '../services/engagement_service.dart';
import 'image_upload_modal.dart';
import 'login_widget.dart';
import 'follow_list_modal.dart';

/// The top section of the profile (Avatar, Bio, Follow Buttons, Stats)
/// This scrolls away with the page.
class ProfileHeader extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String profileUid;
  final bool isMe;

  const ProfileHeader({
    super.key,
    required this.userData,
    required this.profileUid,
    required this.isMe,
  });

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  final EngagementService _engagementService = EngagementService();
  int _topTabIndex = 0; // Local state for Socials/Affiliations/Upcoming tabs

  final Color _envelopeColor = const Color(0xFFF1B255);
  final BoxDecoration _whiteBoxDecoration = const BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.zero,
    boxShadow: [
      BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(1, 1)),
    ],
  );

  bool get _isManaged => widget.userData['isManaged'] == true;
  List<dynamic> get _managers => widget.userData['managers'] ?? [];

  bool get _canEdit {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;
    if (widget.profileUid == currentUid) return true;
    if (_isManaged && _managers.contains(currentUid)) return true;
    return false;
  }

  void _showImageUpload() {
    if (!_canEdit) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) =>
          ImageUploadModal(userId: widget.profileUid),
    );
  }

  void _handleFollow(bool isFollowing) async {
    final user = FirebaseAuth.instance.currentUser;
    final isRealUser = user != null && !user.isAnonymous;

    if (!isRealUser) {
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
      return;
    }

    try {
      if (isFollowing) {
        await _engagementService.unfollowUser(widget.profileUid);
      } else {
        await _engagementService.followUser(widget.profileUid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _showListModal(String title, String collectionName) {
    showDialog(
      context: context,
      builder: (context) => FollowListModal(
        userId: widget.profileUid,
        title: title,
        collectionName: collectionName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return _buildMobileLayout();
        } else {
          return _buildDesktopLayout();
        }
      },
    );
  }

  Widget _buildDesktopLayout() {
    // Fixed aspect ratio container for desktop feel
    return AspectRatio(
      aspectRatio: 8 / 3.5, // Adjusted to be shorter since Nav is gone
      child: Container(
        color: _envelopeColor,
        padding: const EdgeInsets.all(16.0),
        child: Container(
          width: double.infinity,
          decoration: _whiteBoxDecoration,
          padding: const EdgeInsets.all(24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 1, child: _buildProfileInfoContent()),
              const VerticalDivider(
                  width: 48, thickness: 1, color: Colors.black12),
              Expanded(flex: 1, child: _buildRightSideContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Top Box: Fixed 8:5 Aspect Ratio
        AspectRatio(
          aspectRatio: 8 / 5,
          child: Container(
            color: _envelopeColor,
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: _whiteBoxDecoration,
              padding: const EdgeInsets.all(16.0),
              child: _buildProfileInfoContent(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Bottom Box: Flexible Height (expands to content)
        Container(
          width: double.infinity,
          color: _envelopeColor,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Container(
            decoration: _whiteBoxDecoration,
            padding: const EdgeInsets.all(16.0),
            // Let the column define the height
            child: _buildRightSideContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfoContent() {
    final String displayName = widget.userData['displayName'] ?? '';
    final String firstName = widget.userData['firstName'] ?? '';
    final String lastName = widget.userData['lastName'] ?? '';
    final String username = widget.userData['username'] ?? '';
    final String bio = widget.userData['bio'] ?? '';
    final String? photoUrl = widget.userData['photoUrl'];

    final String displayTitle = displayName.isNotEmpty
        ? displayName
        : (firstName.isNotEmpty || lastName.isNotEmpty
        ? '$firstName $lastName'.trim()
        : 'User');

    return ClipRect(
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _showImageUpload,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12),
                          image: photoUrl != null && photoUrl.isNotEmpty
                              ? DecorationImage(
                              image: NetworkImage(photoUrl),
                              fit: BoxFit.cover)
                              : null,
                        ),
                        child: photoUrl == null || photoUrl.isEmpty
                            ? const Icon(Icons.person,
                            size: 50, color: Colors.grey)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.isMe)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StreamBuilder<bool>(
                                stream: _engagementService
                                    .isFollowingStream(widget.profileUid),
                                builder: (context, snap) {
                                  final bool isFollowing = snap.data ?? false;
                                  return GestureDetector(
                                    onTap: () => _handleFollow(isFollowing),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isFollowing
                                            ? Colors.grey[100]
                                            : Colors.transparent,
                                        border: Border.all(color: Colors.black),
                                        borderRadius: BorderRadius.zero,
                                      ),
                                      child: Text(
                                          isFollowing ? "unfollow" : "follow",
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black)),
                                    ),
                                  );
                                },
                              ),
                            ],
                          )
                        else
                          GestureDetector(
                            onTap: () {
                              if (widget.profileUid.isNotEmpty) {
                                context.pushNamed('editInfo',
                                    queryParameters: {
                                      'userId': widget.profileUid
                                    });
                              } else {
                                context.pushNamed('editInfo');
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                border: Border.all(color: Colors.black),
                                borderRadius: BorderRadius.zero,
                              ),
                              child: const Text("edit info",
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black)),
                            ),
                          ),
                        const SizedBox(height: 8),
                        StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('Users')
                                .doc(widget.profileUid)
                                .snapshots(),
                            builder: (context, snap) {
                              int followers = 0;
                              int following = 0;
                              if (snap.hasData && snap.data!.exists) {
                                final data =
                                snap.data!.data() as Map<String, dynamic>;
                                followers = data['followerCount'] ?? 0;
                                following = data['followingCount'] ?? 0;
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => _showListModal(
                                        "Followers", "followers"),
                                    child: Text("$followers followers",
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black,
                                            decoration:
                                            TextDecoration.underline)),
                                  ),
                                  GestureDetector(
                                    onTap: () => _showListModal(
                                        "Following", "following"),
                                    child: Text("$following following",
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black,
                                            decoration:
                                            TextDecoration.underline)),
                                  ),
                                ],
                              );
                            }),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 16),
                Text(displayTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.black)),
                Text('@$username',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.black54)),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(bio,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Colors.black),
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis)),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
          if (_isManaged)
            Positioned(
              top: 12,
              left: -35,
              child: Transform.rotate(
                angle: -0.785,
                child: Material(
                  color: Colors.grey[200],
                  child: InkWell(
                    onTap: _canEdit
                        ? () => context.pushNamed('editInfo',
                        queryParameters: {'userId': widget.profileUid})
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 40),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Text(
                        _canEdit ? "edit managed profile" : "managed profile",
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRightSideContent() {
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 8),
                        _buildTopTab("socials", 0),
                        _buildSeparator(isNav: true),
                        _buildTopTab("affiliations", 1),
                        _buildSeparator(isNav: true),
                        _buildTopTab("upcoming", 2),
                        const SizedBox(width: 8),
                      ]))),
          const Divider(height: 24, thickness: 1, color: Colors.black12),
          // In Mobile Layout, we want this list to expand as needed.
          // In Desktop Layout, it's inside an Expanded column so it fills space.
          // We'll wrap in a Flexible or just let it flow based on parent constraints.
          Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_topTabIndex == 0) _buildSocialsTab(),
                        if (_topTabIndex == 1)
                          const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text("Affiliations List\n(Coming Soon)",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black))),
                        if (_topTabIndex == 2)
                          const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text("Upcoming Cons/Events\n(Coming Soon)",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black))),
                      ]))),
          if (!_isManaged && widget.isMe)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: GestureDetector(
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      context.go('/login');
                    },
                    child: const Text('logout',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          decoration: TextDecoration.underline,
                          fontFamily: 'Roboto',
                        ))),
              ),
            ),
        ]);
  }

  Widget _buildSocialsTab() {
    List<Widget> links = [];
    final xHandle = widget.userData['xHandle'] ?? '';
    final instaHandle = widget.userData['instagramHandle'] ?? '';

    if (xHandle.isNotEmpty)
      links.add(_buildLinkButton(
          "X (Twitter)", '@$xHandle', 'https://x.com/$xHandle'));
    if (instaHandle.isNotEmpty)
      links.add(_buildLinkButton("Instagram", '@$instaHandle',
          'https://instagram.com/$instaHandle'));

    if (links.isEmpty)
      return const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text("No socials linked.",
              style: TextStyle(
                  color: Colors.black54, fontStyle: FontStyle.italic)));
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: links
            .map((w) =>
            Padding(padding: const EdgeInsets.only(bottom: 12), child: w))
            .toList());
  }

  Widget _buildLinkButton(String platform, String handle, String url) {
    return GestureDetector(
        onTap: () => launchUrl(Uri.parse(url)),
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                color: Colors.grey[50],
                borderRadius: BorderRadius.zero),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("$platform: ",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black)),
              Text(handle,
                  style: const TextStyle(
                      color: Colors.black, decoration: TextDecoration.underline))
            ])));
  }

  Widget _buildTopTab(String title, int index) {
    final isActive = _topTabIndex == index;
    return GestureDetector(
        onTap: () => setState(() => _topTabIndex = index),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    decoration:
                    isActive ? TextDecoration.underline : null))));
  }

  Widget _buildSeparator({bool isNav = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text('|',
          style: TextStyle(
              color: isNav ? Colors.black : Colors.grey.shade400)));
}

/// The Navigation Bar (Tabs) for the profile.
/// Typically used inside a SliverPersistentHeader.
class ProfileNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabChanged;
  final bool canEdit;
  final VoidCallback onUploadImage;

  const ProfileNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
    required this.canEdit,
    required this.onUploadImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Center(
        // Wrap with a constrained width to match profile/grid content
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (canEdit) ...[
                    _buildNavTab('editor', 0),
                    _buildSeparator(),
                  ],
                  _buildNavTab('pages', 1),
                  _buildSeparator(),
                  _buildNavTab('works', 2),
                  _buildSeparator(),
                  _buildNavTab('comments', 3),
                  _buildSeparator(),
                  _buildNavTab('mentions', 4),
                  _buildSeparator(),
                  _buildNavTab('collection', 5),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTab(String title, int index) {
    final isActive = currentIndex == index;

    // Modified: removed the logic that showed inline "(upload image)" text.
    // Now it just displays the tab title. The upload action is moved to a secondary bar in ProfilePage.

    return GestureDetector(
        onTap: () => onTabChanged(index),
        child: Center(
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(title,
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                        decoration:
                        isActive ? TextDecoration.underline : null)))));
  }

  Widget _buildSeparator() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text('|', style: TextStyle(color: Colors.black)));
}