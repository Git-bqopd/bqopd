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
      _email = '',
      _firstName = '',
      _lastName = '',
      _street1 = '',
      _street2 = '',
      _city = '',
      _stateName = '',
      _zipCode = '',
      _country = '',
      _bio = '',
      _xHandle = '',
      _instagramHandle = '';
  bool _isLoading = true;
  String? _errorMessage;
  bool _isManaged = false;
  List<dynamic> _managers = [];

  // Used for permission check
  String _profileUid = '';

  final ScrollController _leftStickerScrollController = ScrollController();

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

    // If viewing MY profile and it's loaded in provider
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
      // Viewing SOMEONE ELSE'S (or a Managed) profile
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
      final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
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
      if (mounted)
        setState(() {
          _errorMessage = "Error loading data.";
          _isLoading = false;
        });
    }
  }

  void _populateFields(Map<String, dynamic> data) {
    setState(() {
      _profileUid = data['uid'] ?? '';
      _email = data['email'] ?? '';
      _username = data['username'] ?? '';
      _firstName = data['firstName'] ?? '';
      _lastName = data['lastName'] ?? '';
      _street1 = data['street1'] ?? '';
      _street2 = data['street2'] ?? '';
      _city = data['city'] ?? '';
      _stateName = data['state'] ?? '';
      _zipCode = data['zipCode'] ?? '';
      _country = data['country'] ?? '';
      _bio = data['bio'] ?? '';
      _xHandle = data['xHandle'] ?? '';
      _instagramHandle = data['instagramHandle'] ?? '';
      _isManaged = data['isManaged'] == true;
      _managers = data['managers'] ?? [];
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    try {
      final provider = Provider.of<UserProvider>(context, listen: false);
      provider.removeListener(_onProviderUpdate);
    } catch (_) {}
    _leftStickerScrollController.dispose();
    super.dispose();
  }

  /// Determines if the current logged-in user has permission to edit this profile.
  bool get _canEdit {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;

    // 1. Is it me?
    if (_profileUid == currentUid) return true;

    // 2. Am I a manager of this managed profile?
    if (_isManaged && _managers.contains(currentUid)) return true;

    return false;
  }

  String _buildFormattedAddress() {
    List<String> parts = [];
    if (_firstName.isNotEmpty || _lastName.isNotEmpty) parts.add('$_firstName $_lastName'.trim());
    if (_street1.isNotEmpty) parts.add(_street1);
    if (_street2.isNotEmpty) parts.add(_street2);
    String cityStateZip = '$_city, $_stateName $_zipCode'.trim().replaceAll(RegExp(r'^,\s*|\s*,\s*\$'), '');
    if (cityStateZip.isNotEmpty && cityStateZip != ',') parts.add(cityStateZip);
    if (_country.isNotEmpty) parts.add(_country);
    return parts.join('\n');
  }

  void _showImageUpload() {
    if (!_canEdit) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => ImageUploadModal(userId: _profileUid),
    );
  }

  // Link Launcher Helper
  Future<void> _launchSocial(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.targetUserId == null) {
      // Fallback for "My Profile" tab logic if data hasn't loaded via _fetchOtherUser
      final provider = context.watch<UserProvider>();
      if (!provider.isLoading && provider.userProfile != null && _profileUid.isEmpty) {
        _populateFields(provider.userProfile!);
        _isLoading = false;
      }
    }

    // 8:5 Aspect Ratio Container
    return AspectRatio(
      aspectRatio: 8 / 5,
      child: Container(
        color: const Color(0xFFF1B255), // Manilla Envelope Background
        padding: const EdgeInsets.all(16.0), // Outer Margin
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
            : Column(
          children: [
            // TOP ROW (Contact + Linktree)
            Expanded(
              flex: 4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch, // Allow full height for pinning
                children: [
                  // LEFT STICKER: Contact Info (Takes remaining space, aligned left)
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerLeft, // Pinned to the Left (vertically centered)
                      child: Container(
                        // Constrain max width for the sticker itself
                        constraints: const BoxConstraints(maxWidth: 400), // Increased max width for 2-column layout
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.zero,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 2,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                        // New Layout Structure
                        padding: const EdgeInsets.all(8.0),
                        child: IntrinsicHeight(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ROW 1: Edit Info (Aligned Right)
                              if (_canEdit)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: GestureDetector(
                                    // Navigate to edit page with parameters
                                    onTap: () {
                                      // If we have a valid profile UID, pass it along
                                      if (_profileUid.isNotEmpty) {
                                        context.pushNamed(
                                            'editInfo',
                                            queryParameters: {'userId': _profileUid}
                                        );
                                      } else {
                                        context.pushNamed('editInfo');
                                      }
                                    },
                                    child: const Text('edit info', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                                  ),
                                ),

                              const SizedBox(height: 8),

                              // ROW 2: The Split (Profile Pic | Info)
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Left Column: Profile Picture
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12.0),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 100), // Constraint for profile pic
                                        child: AspectRatio(
                                          aspectRatio: 5/8,
                                          child: Container(
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.person, color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Right Column: Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _firstName.isNotEmpty || _lastName.isNotEmpty
                                                ? '$_firstName $_lastName'.trim()
                                                : 'User',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          if (_isManaged) ...[
                                            const SizedBox(height: 2),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              color: Colors.grey[200],
                                              child: const Text("Managed Profile", style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                                            )
                                          ],
                                          Text(
                                            '@$_username',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              GestureDetector(
                                                onTap: () { },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Colors.black),
                                                    borderRadius: BorderRadius.zero,
                                                  ),
                                                  child: const Text("follow", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              const Text("0 followers", style: TextStyle(fontSize: 10, color: Colors.black)),
                                            ],
                                          ),
                                          if (_bio.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              _bio,
                                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                                              maxLines: 4,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 8),

                              // ROW 3: Logout (Aligned Right) - Only show if it's MY account, not a managed one
                              if (!_isManaged && _profileUid == Provider.of<UserProvider>(context, listen: false).currentUserId)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: GestureDetector(
                                    onTap: () async {
                                      await FirebaseAuth.instance.signOut();
                                      if (mounted) context.go('/login');
                                    },
                                    child: const Text('logout', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // RIGHT STICKER: Socials / Tabs (Pinned Top Right, grows Left/Down)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.zero,
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(1, 1)),
                          ],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min, // Shrink wrap vertically
                          crossAxisAlignment: CrossAxisAlignment.end, // Right align content inside the box
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min, // Shrink wrap horizontally
                              children: [
                                _buildTopTab("socials", 0),
                                _buildSeparator(),
                                _buildTopTab("affiliations", 1),
                                _buildSeparator(),
                                _buildTopTab("upcoming", 2),
                              ],
                            ),
                            const Divider(height: 16, thickness: 1),

                            // Content
                            if (_topTabIndex == 0) _buildSocialsTab(),
                            if (_topTabIndex == 1) const Padding(padding: EdgeInsets.all(8), child: Text("Affiliations List\n(Coming Soon)", textAlign: TextAlign.center)),
                            if (_topTabIndex == 2) const Padding(padding: EdgeInsets.all(8), child: Text("Upcoming Cons/Events\n(Coming Soon)", textAlign: TextAlign.center)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // BOTTOM STICKER: Main Navigation
            SizedBox(
              height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IntrinsicWidth(
                    child: _buildSticker(
                      child: Row(
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
                      ),
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

  Widget _buildSticker({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(1, 1)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }

  Widget _buildSocialsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end, // Right align links
      children: [
        if (_xHandle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  const TextSpan(text: 'X: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(
                    text: '@$_xHandle',
                    style: TextStyle(color: Theme.of(context).primaryColorDark, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = () => _launchSocial('https://x.com/$_xHandle'),
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
                  const TextSpan(text: 'Instagram: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(
                    text: '@$_instagramHandle',
                    style: TextStyle(color: Theme.of(context).primaryColorDark, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = () => _launchSocial('https://instagram.com/$_instagramHandle'),
                  ),
                ],
              ),
            ),
          ),

        if (_xHandle.isEmpty && _instagramHandle.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("No socials linked.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
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
    // Check _canEdit instead of _isMyProfile to support managers uploading to managed profiles
    final showUploadLink = isPagesTab && isActive && _canEdit;

    if (showUploadLink) {
      return FittedBox( // Shrink if narrow
        fit: BoxFit.scaleDown,
        child: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black, fontSize: 14, fontFamily: 'Roboto'),
            children: [
              TextSpan(
                text: title,
                style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                recognizer: TapGestureRecognizer()..onTap = () => widget.onTabChanged(index),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: '(upload image)',
                style: const TextStyle(fontWeight: FontWeight.normal, color: Colors.black),
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
        child: FittedBox( // Shrink if narrow
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
          style: TextStyle(color: isNav ? Colors.black : Colors.grey.shade400)
      ),
    );
  }
}