import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/user_provider.dart';
import 'image_upload_modal.dart';

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
          child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }

    // RESPONSIVE SWITCHER
    return LayoutBuilder(
      builder: (context, constraints) {
        // If width is strictly less than 900px, use the 2-widget stack.
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
                    const VerticalDivider(width: 48, thickness: 1, color: Colors.black12),
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
        AspectRatio(
          aspectRatio: 8 / 5,
          child: Container(
            color: _envelopeColor,
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: _whiteBoxDecoration,
              padding: const EdgeInsets.all(24.0),
              child: _buildRightSideContent(),
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
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Expanded(child: _buildProfileInfoContent()),
                  const Divider(height: 24, thickness: 1, color: Colors.black12),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Edit Button
        if (_canEdit)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
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
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: AspectRatio(
                    aspectRatio: 5 / 8,
                    child: Container(
                      color: Colors.grey[200],
                      child: _photoUrl != null && _photoUrl!.isNotEmpty
                          ? Image.network(
                        _photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                        const Icon(Icons.person, color: Colors.grey),
                      )
                          : const Icon(Icons.person, color: Colors.grey),
                    ),
                  ),
                ),
              ),
              // Text Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName.isNotEmpty
                          ? _displayName
                          : (_firstName.isNotEmpty || _lastName.isNotEmpty
                          ? '$_firstName $_lastName'.trim()
                          : 'User'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    if (_isManaged) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        color: Colors.grey[200],
                        child: const Text("Managed Profile",
                            style: TextStyle(
                                fontSize: 9, fontStyle: FontStyle.italic)),
                      )
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '@$_username',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {},
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black),
                              borderRadius: BorderRadius.zero,
                            ),
                            child: const Text("follow",
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text("0 followers",
                            style:
                            TextStyle(fontSize: 12, color: Colors.black)),
                      ],
                    ),
                    if (_bio.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _bio,
                        style: const TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // Logout
        if (!_isManaged &&
            _profileUid ==
                Provider.of<UserProvider>(context, listen: false).currentUserId)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                context.go('/login');
              },
              child: const Text('logout',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
            ),
          ),
      ],
    );
  }

  Widget _buildRightSideContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs Header
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _buildTopTab("socials", 0),
            _buildSeparator(),
            _buildTopTab("affiliations", 1),
            _buildSeparator(),
            _buildTopTab("upcoming", 2),
          ],
        ),
        const Divider(height: 24, thickness: 1),
        // Tab Content
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_topTabIndex == 0) _buildSocialsTab(),
                if (_topTabIndex == 1)
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text("Affiliations List\n(Coming Soon)",
                          textAlign: TextAlign.right)),
                if (_topTabIndex == 2)
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text("Upcoming Cons/Events\n(Coming Soon)",
                          textAlign: TextAlign.right)),
              ],
            ),
          ),
        ),
      ],
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

  Widget _buildSocialsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_xHandle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  const TextSpan(
                      text: 'X: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(
                    text: '@$_xHandle',
                    style: TextStyle(
                        color: Theme.of(context).primaryColorDark,
                        decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _launchSocial('https://x.com/$_xHandle'),
                  ),
                ],
              ),
            ),
          ),
        if (_instagramHandle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  const TextSpan(
                      text: 'Instagram: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(
                    text: '@$_instagramHandle',
                    style: TextStyle(
                        color: Theme.of(context).primaryColorDark,
                        decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _launchSocial(
                          'https://instagram.com/$_instagramHandle'),
                  ),
                ],
              ),
            ),
          ),
        if (_xHandle.isEmpty && _instagramHandle.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("No socials linked.",
                style:
                TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ),
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
            color: Theme.of(context).primaryColorDark,
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