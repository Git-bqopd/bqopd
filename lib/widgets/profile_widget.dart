import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/user_provider.dart';
import 'image_upload_modal.dart';
import 'login_widget.dart';

class ProfileWidget extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTabChanged; // Callback for bottom tabs
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
  // Top Right Tabs: 0=Socials, 1=Affiliations, 2=Upcoming
  int _topTabIndex = 0;

  String _username = '',
      _displayName = '',
      _firstName = '',
      _lastName = '',
      _bio = '',
      _xHandle = '',
      _instagramHandle = '',
      _profileUid = '';
  String? _photoUrl; // Add photoUrl state
  bool _isLoading = true;
  String? _errorMessage;
  bool _isManaged = false;
  List<dynamic> _managers = [];

  // Define the common box decoration for white cards
  final BoxDecoration _whiteBoxDecoration = const BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.zero,
    boxShadow: [
      BoxShadow(
        color: Colors.black12,
        blurRadius: 2,
        offset: Offset(1, 1),
      ),
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
        setState(() {
          _errorMessage = "User not found";
          _isLoading = false;
        });
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
      final doc =
      await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (doc.exists && mounted) {
        _populateFields(doc.data()!);
        setState(() => _isLoading = false);
      } else if (mounted) {
        setState(() {
          _errorMessage = "User not found.";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error loading data.";
          _isLoading = false;
        });
      }
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
      builder: (BuildContext dialogContext) =>
          ImageUploadModal(userId: _profileUid),
    );
  }

  Future<void> _launchSocial(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  // --- FOLLOW LOGIC ---
  void _handleFollow() {
    final user = FirebaseAuth.instance.currentUser;
    final isRealUser = user != null && !user.isAnonymous;

    if (!isRealUser) {
      // User is not authenticated, show login modal
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
                _loadData();
              },
            ),
          ),
        ),
      );
      return;
    }

    // Logic for follow functionality will go here
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Follow logic coming soon!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.targetUserId == null) {
      final provider = context.watch<UserProvider>();
      if (!provider.isLoading &&
          provider.userProfile != null &&
          _profileUid.isEmpty) {
        _populateFields(provider.userProfile!);
        _isLoading = false;
      }
    }

    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
          child:
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }

    // RESPONSIVE SWITCHER
    return LayoutBuilder(
      builder: (context, constraints) {
        // If width is strictly less than 600px, use the 2-widget stack.
        // Otherwise, use the unified desktop widget.
        if (constraints.maxWidth < 600) {
          return _buildMobileLayout();
        } else {
          return _buildDesktopLayout();
        }
      },
    );
  }

  // --- DESKTOP LAYOUT (Unified) ---
  Widget _buildDesktopLayout() {
    return AspectRatio(
      aspectRatio: 8 / 5,
      child: Container(
        color: _envelopeColor,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Unified White Box (Split Vertical)
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                decoration: _whiteBoxDecoration,
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT COLUMN
                    Expanded(flex: 1, child: _buildProfileInfoContent()),
                    // DIVIDER
                    const VerticalDivider(
                        width: 48, thickness: 1, color: Colors.black12),
                    // RIGHT COLUMN
                    Expanded(flex: 1, child: _buildRightSideContent()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Bottom Nav Sticker (Desktop only)
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

  // --- MOBILE LAYOUT (Split) ---
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Widget 1: Left Side (Profile Info)
        // On mobile, profile info comes first usually
        AspectRatio(
          aspectRatio: 8 / 5, // Keep sticker ratio
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
        // Widget 2: Right Side + Controller Links
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
                  const Divider(
                      height: 24, thickness: 1, color: Colors.black12),
                  // Nav links inside the box for mobile
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildNavLinksRow(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- COMPONENT BUILDERS ---

  Widget _buildProfileInfoContent() {
    final String displayTitle = _displayName.isNotEmpty
        ? _displayName
        : (_firstName.isNotEmpty || _lastName.isNotEmpty
        ? '$_firstName $_lastName'.trim()
        : 'User');

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Top Section: Photo & Stats/Follow Side-by-Side
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circular Profile Photo
              GestureDetector(
                onTap: _showImageUpload, // Tap photo to upload
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12),
                    image: _photoUrl != null && _photoUrl!.isNotEmpty
                        ? DecorationImage(
                      image: NetworkImage(_photoUrl!),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: _photoUrl == null || _photoUrl!.isEmpty
                      ? const Icon(Icons.person, size: 50, color: Colors.grey)
                      : null,
                ),
              ),
              const SizedBox(width: 24),
              // Stats / Follow Button Column
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Follow Button
                  GestureDetector(
                    onTap: _handleFollow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black),
                        borderRadius: BorderRadius.zero, // Sharp look
                      ),
                      child: const Text("follow",
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Placeholder Stats
                  const Text("0 followers",
                      style: TextStyle(fontSize: 12, color: Colors.black)),
                  const Text("0 following",
                      style: TextStyle(fontSize: 12, color: Colors.black)),
                ],
              )
            ],
          ),

          const SizedBox(height: 16),

          // 2. Name & Handle
          Text(
            displayTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black),
          ),
          if (_isManaged)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.grey[200],
              child: const Text("Managed Profile",
                  style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: Colors.black)),
            ),
          Text(
            '@$_username',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),

          // 3. Bio
          if (_bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                _bio,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.black),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // 4. Admin Actions (Edit / Logout)
          Wrap(
            spacing: 20,
            alignment: WrapAlignment.center,
            children: [
              if (_canEdit)
                GestureDetector(
                  onTap: () {
                    if (_profileUid.isNotEmpty) {
                      context.pushNamed('editInfo',
                          queryParameters: {'userId': _profileUid});
                    } else {
                      context.pushNamed('editInfo');
                    }
                  },
                  child: const Text('edit info',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                ),
              if (!_isManaged &&
                  _profileUid ==
                      Provider.of<UserProvider>(context, listen: false)
                          .currentUserId)
                GestureDetector(
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!context.mounted) return;
                    context.go('/login');
                  },
                  child: const Text('logout',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightSideContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs Header - Centered link menu
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
              ],
            ),
          ),
        ),
        const Divider(height: 24, thickness: 1, color: Colors.black12),
        // Tab Content - Centered "Link Tree" style
        Expanded(
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
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialsTab() {
    bool hasLinks = false;
    List<Widget> links = [];

    if (_xHandle.isNotEmpty) {
      hasLinks = true;
      links.add(_buildLinkButton(
          "X (Twitter)", '@$_xHandle', 'https://x.com/$_xHandle'));
    }

    if (_instagramHandle.isNotEmpty) {
      hasLinks = true;
      links.add(_buildLinkButton("Instagram", '@$_instagramHandle',
          'https://instagram.com/$_instagramHandle'));
    }

    if (!hasLinks) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text("No socials linked.",
            style:
            TextStyle(color: Colors.black54, fontStyle: FontStyle.italic)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: links
          .map((w) => Padding(
          padding: const EdgeInsets.only(bottom: 12), child: w))
          .toList(),
    );
  }

  Widget _buildLinkButton(String platform, String handle, String url) {
    return GestureDetector(
      onTap: () => _launchSocial(url),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          color: Colors.grey[50],
          borderRadius: BorderRadius.zero, // Sharp aesthetic
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("$platform: ",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.black)),
            Text(handle,
                style: const TextStyle(
                    color: Colors.black, decoration: TextDecoration.underline)),
          ],
        ),
      ),
    );
  }

  Widget _buildNavLinksRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_canEdit) ...[
          _buildNavTab('editor', 0),
          _buildSeparator(isNav: true),
        ],
        _buildNavTab('pages', 1),
        _buildSeparator(isNav: true),
        _buildNavTab('works', 2),
        _buildSeparator(isNav: true),
        _buildNavTab('comments', 3),
        _buildSeparator(isNav: true),
        _buildNavTab('mentions', 4),
        _buildSeparator(isNav: true),
        _buildNavTab('collection', 5),
      ],
    );
  }

  Widget _buildTopTab(String title, int index) {
    final isActive = _topTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _topTabIndex = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.black,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            decoration: isActive ? TextDecoration.underline : null,
          ),
        ),
      ),
    );
  }

  Widget _buildNavTab(String title, int index) {
    final isActive = widget.currentIndex == index;
    final isPagesTab = index == 1;
    final showUploadLink = isPagesTab && isActive && _canEdit;

    if (showUploadLink) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
                color: Colors.black, fontSize: 14, fontFamily: 'Roboto'),
            children: [
              TextSpan(
                text: title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => widget.onTabChanged(index),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: '(upload image)',
                style: const TextStyle(
                    fontWeight: FontWeight.normal, color: Colors.black),
                recognizer: TapGestureRecognizer()..onTap = _showImageUpload,
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => widget.onTabChanged(index),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            style: TextStyle(
              color: Colors.black,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              decoration: isActive ? TextDecoration.underline : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeparator({bool isNav = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text('|',
          style: TextStyle(color: isNav ? Colors.black : Colors.grey.shade400)),
    );
  }
}