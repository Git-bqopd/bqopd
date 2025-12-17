import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/user_provider.dart';
import '../pages/fanzine_page.dart';
import 'image_upload_modal.dart';

class ProfileWidget extends StatefulWidget {
  final int currentIndex;
  final VoidCallback onEditorTapped;   // Callback for Editor Tab
  final VoidCallback onFanzinesTapped; // Callback for Fanzines Tab
  final VoidCallback onPagesTapped;    // Callback for Pages Tab
  final String? targetUserId; // NULL = Current Logged In User

  // NEW: Optional override for the "primary action" link
  final String? actionLinkText;
  final VoidCallback? onActionLinkTapped;

  const ProfileWidget({
    super.key,
    required this.currentIndex,
    required this.onEditorTapped,
    required this.onFanzinesTapped,
    required this.onPagesTapped,
    this.targetUserId,
    this.actionLinkText,
    this.onActionLinkTapped,
  });

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> {
  String _username = '', _email = '', _firstName = '', _lastName = '', _street1 = '', _street2 = '', _city = '', _stateName = '', _zipCode = '', _country = '';
  bool _isLoading = true;
  String? _errorMessage;

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

    // CASE 1: Viewing MY profile
    if (currentUid != null && targetUid == currentUid) {
      // Use Provider Data (Synchronous/Cached)
      final data = provider.userProfile;
      if (data != null) {
        _populateFields(data);
        setState(() => _isLoading = false);
      } else if (provider.isLoading) {
        // Wait for provider to finish
        setState(() => _isLoading = true);
        provider.addListener(_onProviderUpdate);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = "User data not found.";
        });
      }
    }
    // CASE 2: Viewing SOMEONE ELSE'S profile (or not logged in)
    else {
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
      if (mounted) setState(() { _errorMessage = "Error loading data."; _isLoading = false; });
    }
  }

  void _populateFields(Map<String, dynamic> data) {
    setState(() {
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
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    // Safety check in case we added listener
    try {
      final provider = Provider.of<UserProvider>(context, listen: false);
      provider.removeListener(_onProviderUpdate);
    } catch (_) {}
    super.dispose();
  }

  bool get _isMyProfile {
    final provider = Provider.of<UserProvider>(context, listen: false);
    return widget.targetUserId == null || widget.targetUserId == provider.currentUserId;
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

  @override
  Widget build(BuildContext context) {
    // If it's my profile, we can watch the provider for live updates
    if (_isMyProfile) {
      final provider = context.watch<UserProvider>();
      if (!provider.isLoading && provider.userProfile != null) {
        // This ensures the UI updates if the provider gets new data while we are looking at it
        _populateFields(provider.userProfile!);
        _isLoading = false;
      }
    }

    final linkStyle = TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark);

    // REMOVED: borderRadius variable
    // final borderRadius = BorderRadius.circular(12.0);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF1B255),
        // borderRadius: borderRadius // REMOVED
      ),
      child: ClipRect( // CHANGED from ClipRRect to ClipRect
        // borderRadius: borderRadius, // REMOVED
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : Column(
            children: [
              Expanded(
                child: Center(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Username: $_username'),
                                  const SizedBox(height: 4),
                                  if (_isMyProfile) ...[
                                    Text('Email: $_email'),
                                    const SizedBox(height: 12),
                                  ],
                                  if (_buildFormattedAddress().isNotEmpty) ...[
                                    const Text('mailing address:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(_buildFormattedAddress()),
                                  ] else ...[
                                    const Text('Address: Not Provided'),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),

                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 1. Dynamic Link
                                RichText(
                                  text: TextSpan(
                                    text: widget.actionLinkText ?? 'view fanzine',
                                    style: linkStyle,
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = widget.onActionLinkTapped ??
                                              () {
                                            context.push('/fanzine');
                                          },
                                  ),
                                ),

                                // 2. Edit Controls (Only if MY profile)
                                if (_isMyProfile) ...[
                                  const SizedBox(height: 10),
                                  RichText(
                                    text: TextSpan(
                                      text: 'edit info',
                                      style: linkStyle,
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => context.pushNamed('editInfo'),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  RichText(
                                    text: TextSpan(
                                      text: 'upload image',
                                      style: linkStyle,
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          final uid = Provider.of<UserProvider>(context, listen: false).currentUserId;
                                          if (uid == null) return;
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (BuildContext dialogContext) => ImageUploadModal(userId: uid),
                                          );
                                        },
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  RichText(
                                    text: TextSpan(
                                      text: 'logout',
                                      style: linkStyle,
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () async {
                                          await FirebaseAuth.instance.signOut();
                                          if (mounted) context.go('/login');
                                        },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isMyProfile) ...[
                      GestureDetector(
                        onTap: widget.onEditorTapped,
                        child: Text(
                          'editor',
                          style: TextStyle(
                            color: Theme.of(context).primaryColorDark,
                            fontWeight: widget.currentIndex == 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text('|', style: TextStyle(color: Theme.of(context).primaryColorDark)),
                      ),
                    ],
                    GestureDetector(
                      onTap: widget.onFanzinesTapped,
                      child: Text(
                        'fanzines',
                        style: TextStyle(
                          color: Theme.of(context).primaryColorDark,
                          fontWeight: widget.currentIndex == 1 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('|', style: TextStyle(color: Theme.of(context).primaryColorDark)),
                    ),
                    GestureDetector(
                      onTap: widget.onPagesTapped,
                      child: Text(
                        'pages',
                        style: TextStyle(
                          color: Theme.of(context).primaryColorDark,
                          fontWeight: widget.currentIndex == 2 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}