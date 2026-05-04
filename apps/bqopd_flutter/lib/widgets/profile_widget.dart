import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'image_upload_modal.dart';
import 'follow_list_modal.dart';
import 'package:bqopd_models/bqopd_models.dart';
import 'package:bqopd_core/bqopd_core.dart';

/// Renders the top section of a unified profile.
class ProfileHeader extends StatefulWidget {
  final UserProfile userData;
  final String profileUid;
  final bool isMe;
  final bool isFollowing;
  final VoidCallback onFollowToggle;
  final bool showAsHashtag; // Controls hashtag display logic based purely on active tab

  const ProfileHeader({
    super.key,
    required this.userData,
    required this.profileUid,
    required this.isMe,
    required this.isFollowing,
    required this.onFollowToggle,
    this.showAsHashtag = false,
  });

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  int _topTabIndex = 0;

  final Color _envelopeColor = const Color(0xFFF1B255);
  final BoxDecoration _whiteBoxDecoration = const BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.zero,
    boxShadow: [
      BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(1, 1)),
    ],
  );

  bool get _isManaged => widget.userData.isManaged;
  List<dynamic> get _managers => widget.userData.managers;

  bool get _canManage {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;
    return _isManaged && _managers.contains(currentUid);
  }

  void _showImageUpload() {
    if (!widget.isMe && !_canManage) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) =>
          ImageUploadModal(userId: widget.profileUid),
    );
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
    return AspectRatio(
      aspectRatio: 8 / 3.5,
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
              const VerticalDivider(width: 48, thickness: 1, color: Colors.black12),
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
        Container(
          width: double.infinity,
          color: _envelopeColor,
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: _whiteBoxDecoration,
            padding: const EdgeInsets.all(16.0),
            child: _buildRightSideContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfoContent() {
    String displayTitle = widget.userData.displayName;
    final String username = widget.userData.username;
    final String bio = widget.userData.bio;
    final String photoUrl = widget.userData.photoUrl;

    // Apply Hashtag Formatting Logic purely based on what we are currently looking at
    if (widget.showAsHashtag) {
      displayTitle = "#${username.replaceAll('-', '_')}";
    } else if (displayTitle.isEmpty) {
      displayTitle = 'User';
    }

    int followers = widget.userData.followerCount;
    int following = widget.userData.followingCount;

    return ClipRect(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                      image: photoUrl.isNotEmpty
                          ? DecorationImage(
                          image: NetworkImage(photoUrl),
                          fit: BoxFit.cover)
                          : null,
                    ),
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.person, size: 50, color: Colors.grey)
                        : null,
                  ),
                ),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.isMe)
                      GestureDetector(
                        onTap: widget.onFollowToggle,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.isFollowing ? Colors.grey[100] : Colors.transparent,
                            border: Border.all(color: Colors.black),
                          ),
                          child: Text(widget.isFollowing ? "unfollow" : "follow",
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () => context.pushNamed('editInfo', queryParameters: {'userId': widget.profileUid}),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black),
                          ),
                          child: const Text("edit info",
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _showListModal("Followers", "followers"),
                          child: Text("$followers followers",
                              style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
                        ),
                        GestureDetector(
                          onTap: () => _showListModal("Following", "following"),
                          child: Text("$following following",
                              style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 16),
            Text(displayTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),

            // Hide the redundant @handle if we are viewing this as a hashtag feed
            if (!widget.showAsHashtag)
              Text('@$username',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black54)),

            if (_isManaged) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _canManage ? () => context.pushNamed('editInfo', queryParameters: {'userId': widget.profileUid}) : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  color: _canManage ? Colors.black.withValues(alpha: 0.05) : Colors.grey[50],
                  child: Text(
                    _canManage ? "EDIT MANAGED PROFILE" : "MANAGED PROFILE",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: _canManage ? Colors.indigo : Colors.black54,
                      letterSpacing: 2.0,
                      decoration: _canManage ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ),
            ],

            if (bio.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis)),
            ],
            const SizedBox(height: 20),
          ],
        ),
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
          Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                  child: Column(
                      children: [
                        if (_topTabIndex == 0) _buildSocialsTab(),
                        if (_topTabIndex == 1) const Padding(padding: EdgeInsets.all(16), child: Text("Affiliations Coming Soon")),
                        if (_topTabIndex == 2) const Padding(padding: EdgeInsets.all(16), child: Text("Upcoming Events Coming Soon")),
                      ]))),
          if (!_isManaged && widget.isMe)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: GestureDetector(
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!mounted) return;
                      context.go('/login');
                    },
                    child: const Text('logout',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ))),
              ),
            ),
        ]);
  }

  Widget _buildSocialsTab() {
    List<Widget> links = [];
    final xHandle = widget.userData.xHandle ?? '';
    final instaHandle = widget.userData.instagramHandle ?? '';
    final githubHandle = widget.userData.githubHandle ?? '';

    if (xHandle.isNotEmpty) links.add(_buildLinkButton("X", '@$xHandle', 'https://x.com/$xHandle'));
    if (instaHandle.isNotEmpty) links.add(_buildLinkButton("Instagram", '@$instaHandle', 'https://instagram.com/$instaHandle'));
    if (githubHandle.isNotEmpty) links.add(_buildLinkButton("GitHub", '@$githubHandle', 'https://github.com/$githubHandle'));

    if (links.isEmpty) return const Padding(padding: EdgeInsets.all(16.0), child: Text("No socials linked.", style: TextStyle(fontStyle: FontStyle.italic)));
    return Column(children: links.map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w)).toList());
  }

  Widget _buildLinkButton(String platform, String handle, String url) {
    return GestureDetector(
        onTap: () => launchUrl(Uri.parse(url)),
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(border: Border.all(color: Colors.black12), color: Colors.grey[50]),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("$platform: ", style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(handle, style: const TextStyle(decoration: TextDecoration.underline))
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
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    decoration: isActive ? TextDecoration.underline : null))));
  }

  Widget _buildSeparator({bool isNav = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text('|', style: TextStyle(color: isNav ? Colors.black : Colors.grey.shade400)));
}

class ProfileNavBar extends StatelessWidget {
  final List<String> tabTitles;
  final int currentIndex;
  final Function(int) onTabChanged;
  final bool canEdit;
  final VoidCallback onUploadImage;

  const ProfileNavBar({
    super.key,
    required this.tabTitles,
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(tabTitles.length, (i) {
              final isActive = currentIndex == i;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: GestureDetector(
                  onTap: () => onTabChanged(i),
                  child: Text(
                    tabTitles[i],
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      decoration: isActive ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}