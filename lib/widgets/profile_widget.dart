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
import 'follow_list_modal.dart'; // NEW

class ProfileWidget extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTabChanged;
  final String? targetUserId;

  const ProfileWidget({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
    this.targetUserId,
  });

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> {
  final EngagementService _engagementService = EngagementService();
  int _topTabIndex = 0;

  String _username = '',
      _displayName = '',
      _firstName = '',
      _lastName = '',
      _bio = '',
      _xHandle = '',
      _instagramHandle = '',
      _profileUid = '';
  String? _photoUrl;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isManaged = false;
  List<dynamic> _managers = [];

  final BoxDecoration _whiteBoxDecoration = const BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.zero,
    boxShadow: [
      BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(1, 1)),
    ],
  );

  final Color _envelopeColor = const Color(0xFFF1B255);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ProfileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetUserId != widget.targetUserId) {
      _loadData();
    }
  }

  void _loadData() {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    final targetUid = widget.targetUserId ?? currentUid;

    if (currentUid != null && targetUid == currentUid) {
      final data = provider.userProfile;
      if (data != null) {
        _populateFields(data);
        setState(() => _isLoading = false);
      } else if (provider.isLoading) {
        setState(() => _isLoading = true);
        provider.addListener(_onProviderUpdate);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = "User data not found.";
        });
      }
    } else {
      if (targetUid == null) {
        setState(() { _errorMessage = "User not found"; _isLoading = false; });
        return;
      }
      _fetchOtherUser(targetUid);
    }
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    final provider = Provider.of<UserProvider>(context, listen: false);
    if (!provider.isLoading) {
      provider.removeListener(_onProviderUpdate);
      if (provider.userProfile != null) {
        _populateFields(provider.userProfile!);
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchOtherUser(String uid) async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (doc.exists && mounted) {
        _populateFields(doc.data()!);
        setState(() => _isLoading = false);
      } else if (mounted) {
        setState(() { _errorMessage = "User not found."; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) { setState(() { _errorMessage = "Error loading data."; _isLoading = false; }); }
    }
  }

  void _populateFields(Map<String, dynamic> data) {
    setState(() {
      _username = data['username'] ?? '';
      _displayName = data['displayName'] ?? '';
      _firstName = data['firstName'] ?? '';
      _lastName = data['lastName'] ?? '';
      _bio = data['bio'] ?? '';
      _xHandle = data['xHandle'] ?? '';
      _instagramHandle = data['instagramHandle'] ?? '';
      _profileUid = data['uid'] ?? '';
      _isManaged = data['isManaged'] == true;
      _managers = data['managers'] ?? [];
      _photoUrl = data['photoUrl'];
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    try {
      final provider = Provider.of<UserProvider>(context, listen: false);
      provider.removeListener(_onProviderUpdate);
    } catch (_) {}
    super.dispose();
  }

  bool get _canEdit {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;
    if (_profileUid == currentUid) return true;
    if (_isManaged && _managers.contains(currentUid)) return true;
    return false;
  }

  void _showImageUpload() {
    if (!_canEdit) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => ImageUploadModal(userId: _profileUid),
    );
  }

  // --- FOLLOW LOGIC ---
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
              onTap: () { Navigator.pop(context); context.go('/register'); },
              onLoginSuccess: () { Navigator.pop(context); _loadData(); },
            ),
          ),
        ),
      );
      return;
    }

    try {
      if (isFollowing) {
        await _engagementService.unfollowUser(_profileUid);
      } else {
        await _engagementService.followUser(_profileUid);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showListModal(String title, String collectionName) {
    showDialog(
      context: context,
      builder: (context) => FollowListModal(
        userId: _profileUid,
        title: title,
        collectionName: collectionName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.targetUserId == null) {
      final provider = context.watch<UserProvider>();
      if (!provider.isLoading && provider.userProfile != null && _profileUid.isEmpty) {
        _populateFields(provider.userProfile!);
        _isLoading = false;
      }
    }

    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }

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
      aspectRatio: 8 / 5,
      child: Container(
        color: _envelopeColor,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              flex: 4,
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
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IntrinsicWidth(
                    child: Container(
                      decoration: _whiteBoxDecoration,
                      padding: const EdgeInsets.all(12),
                      child: _buildNavLinksRow(),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        AspectRatio(
          aspectRatio: 8 / 5,
          child: Container(
            color: _envelopeColor,
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: _whiteBoxDecoration,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(child: _buildRightSideContent()),
                  const Divider(height: 24, thickness: 1, color: Colors.black12),
                  SingleChildScrollView(scrollDirection: Axis.horizontal, child: _buildNavLinksRow()),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfoContent() {
    final String displayTitle = _displayName.isNotEmpty
        ? _displayName
        : (_firstName.isNotEmpty || _lastName.isNotEmpty ? '$_firstName $_lastName'.trim() : 'User');

    final provider = Provider.of<UserProvider>(context);
    final bool isMe = provider.currentUserId == _profileUid;

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
                          image: _photoUrl != null && _photoUrl!.isNotEmpty
                              ? DecorationImage(image: NetworkImage(_photoUrl!), fit: BoxFit.cover)
                              : null,
                        ),
                        child: _photoUrl == null || _photoUrl!.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StreamBuilder<bool>(
                                stream: _engagementService.isFollowingStream(_profileUid),
                                builder: (context, snap) {
                                  final bool isFollowing = snap.data ?? false;
                                  return GestureDetector(
                                    onTap: () => _handleFollow(isFollowing),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isFollowing ? Colors.grey[100] : Colors.transparent,
                                        border: Border.all(color: Colors.black),
                                        borderRadius: BorderRadius.zero,
                                      ),
                                      child: Text(isFollowing ? "unfollow" : "follow",
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                                    ),
                                  );
                                },
                              ),
                            ],
                          )
                        else
                        // Edit Info Button (Sticker Style)
                          GestureDetector(
                            onTap: () {
                              if (_profileUid.isNotEmpty) {
                                context.pushNamed('editInfo', queryParameters: {'userId': _profileUid});
                              } else {
                                context.pushNamed('editInfo');
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                border: Border.all(color: Colors.black),
                                borderRadius: BorderRadius.zero,
                              ),
                              child: const Text("edit info",
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                            ),
                          ),
                        const SizedBox(height: 8),

                        // Stats Section
                        StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance.collection('Users').doc(_profileUid).snapshots(),
                            builder: (context, snap) {
                              int followers = 0;
                              int following = 0;
                              if (snap.hasData && snap.data!.exists) {
                                final data = snap.data!.data() as Map<String, dynamic>;
                                followers = data['followerCount'] ?? 0;
                                following = data['followingCount'] ?? 0;
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => _showListModal("Followers", "followers"),
                                    child: Text("$followers followers", style: const TextStyle(fontSize: 12, color: Colors.black, decoration: TextDecoration.underline)),
                                  ),
                                  GestureDetector(
                                    onTap: () => _showListModal("Following", "following"),
                                    child: Text("$following following", style: const TextStyle(fontSize: 12, color: Colors.black, decoration: TextDecoration.underline)),
                                  ),
                                ],
                              );
                            }
                        ),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 16),
                Text(displayTitle, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black)),
                Text('@$_username', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                if (_bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text(_bio, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.black), maxLines: 6, overflow: TextOverflow.ellipsis)),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
          // Corner Banner/Ribbon for Managed Profiles
          if (_isManaged)
            Positioned(
              top: 12,
              left: -35,
              child: Transform.rotate(
                angle: -0.785, // -45 degrees in radians
                child: Material(
                  color: Colors.grey[200], // Match placeholder image background
                  child: InkWell(
                    onTap: _canEdit
                        ? () => context.pushNamed('editInfo', queryParameters: {'userId': _profileUid})
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 40),
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
    final provider = Provider.of<UserProvider>(context, listen: false);
    final bool isMe = provider.currentUserId == _profileUid;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(width: 8), _buildTopTab("socials", 0), _buildSeparator(isNav: true), _buildTopTab("affiliations", 1), _buildSeparator(isNav: true), _buildTopTab("upcoming", 2), const SizedBox(width: 8),
      ]))),
      const Divider(height: 24, thickness: 1, color: Colors.black12),
      Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (_topTabIndex == 0) _buildSocialsTab(),
        if (_topTabIndex == 1) const Padding(padding: EdgeInsets.all(16), child: Text("Affiliations List\n(Coming Soon)", textAlign: TextAlign.center, style: TextStyle(color: Colors.black))),
        if (_topTabIndex == 2) const Padding(padding: EdgeInsets.all(16), child: Text("Upcoming Cons/Events\n(Coming Soon)", textAlign: TextAlign.center, style: TextStyle(color: Colors.black))),
      ]))),
      // Logout Button positioned at the very bottom right
      if (!_isManaged && isMe)
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
                      color: Colors.black, // Color changed to black
                      decoration: TextDecoration.underline,
                      fontFamily: 'Roboto', // Match socials/nav font
                    ))),
          ),
        ),
    ]);
  }

  Widget _buildSocialsTab() {
    List<Widget> links = [];
    if (_xHandle.isNotEmpty) links.add(_buildLinkButton("X (Twitter)", '@$_xHandle', 'https://x.com/$_xHandle'));
    if (_instagramHandle.isNotEmpty) links.add(_buildLinkButton("Instagram", '@$_instagramHandle', 'https://instagram.com/$_instagramHandle'));

    if (links.isEmpty) return const Padding(padding: EdgeInsets.all(16.0), child: Text("No socials linked.", style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: links.map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w)).toList());
  }

  Widget _buildLinkButton(String platform, String handle, String url) {
    return GestureDetector(onTap: () => launchUrl(Uri.parse(url)), child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), margin: const EdgeInsets.symmetric(horizontal: 24), decoration: BoxDecoration(border: Border.all(color: Colors.black12), color: Colors.grey[50], borderRadius: BorderRadius.zero), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("$platform: ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)), Text(handle, style: const TextStyle(color: Colors.black, decoration: TextDecoration.underline))])));
  }

  Widget _buildNavLinksRow() {
    return Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (_canEdit) ...[_buildNavTab('editor', 0), _buildSeparator(isNav: true)],
      _buildNavTab('pages', 1), _buildSeparator(isNav: true), _buildNavTab('works', 2), _buildSeparator(isNav: true), _buildNavTab('comments', 3), _buildSeparator(isNav: true), _buildNavTab('mentions', 4), _buildSeparator(isNav: true), _buildNavTab('collection', 5),
    ]);
  }

  Widget _buildTopTab(String title, int index) {
    final isActive = _topTabIndex == index;
    return GestureDetector(onTap: () => setState(() => _topTabIndex = index), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Text(title, style: TextStyle(fontSize: 12, color: Colors.black, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, decoration: isActive ? TextDecoration.underline : null))));
  }

  Widget _buildNavTab(String title, int index) {
    final isActive = widget.currentIndex == index;
    final isPagesTab = index == 1;
    final showUploadLink = isPagesTab && isActive && _canEdit;

    if (showUploadLink) {
      return FittedBox(fit: BoxFit.scaleDown, child: RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 14, fontFamily: 'Roboto'), children: [
        TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () => widget.onTabChanged(index)),
        const TextSpan(text: ' '),
        TextSpan(text: '(upload image)', style: const TextStyle(fontWeight: FontWeight.normal, color: Colors.black), recognizer: TapGestureRecognizer()..onTap = _showImageUpload),
      ])));
    }
    return GestureDetector(onTap: () => widget.onTabChanged(index), child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(title, style: TextStyle(color: Colors.black, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, decoration: isActive ? TextDecoration.underline : null)))));
  }

  Widget _buildSeparator({bool isNav = false}) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text('|', style: TextStyle(color: isNav ? Colors.black : Colors.grey.shade400)));
}