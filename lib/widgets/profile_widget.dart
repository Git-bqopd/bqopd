import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
import '../pages/fanzine_page.dart';
import '../pages/edit_info_page.dart';
import 'image_upload_modal.dart';

class ProfileWidget extends StatefulWidget {
  final int currentIndex;
  final VoidCallback onEditorTapped;   // Callback for Editor Tab
  final VoidCallback onFanzinesTapped; // Callback for Fanzines Tab
  final VoidCallback onPagesTapped;    // Callback for Pages Tab
  final String? targetUserId; // NULL = Current Logged In User

  const ProfileWidget({
    super.key,
    required this.currentIndex,
    required this.onEditorTapped,
    required this.onFanzinesTapped,
    required this.onPagesTapped,
    this.targetUserId,
  });

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  String _username = '', _email = '', _firstName = '', _lastName = '', _street1 = '', _street2 = '', _city = '', _stateName = '', _zipCode = '', _country = '';
  bool _isLoading = true;
  String? _errorMessage;

  // Is this the currently logged-in user's profile?
  bool get _isMyProfile {
    if (widget.targetUserId == null) return true;
    return currentUser?.uid == widget.targetUserId;
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void didUpdateWidget(covariant ProfileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetUserId != widget.targetUserId) {
      _loadUserData();
    }
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    // Determine which UID to fetch
    final uidToFetch = widget.targetUserId ?? currentUser?.uid;

    if (uidToFetch != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(uidToFetch)
            .get();

        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
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
          });
        } else if (mounted) {
          // Fallback logic: If UID doc doesn't exist, check Email (legacy migration)
          if (widget.targetUserId == null && currentUser?.email != null) {
            final emailDoc = await FirebaseFirestore.instance
                .collection('Users')
                .doc(currentUser!.email)
                .get();

            if (emailDoc.exists) {
              final data = emailDoc.data() as Map<String, dynamic>;
              setState(() {
                _email = currentUser!.email ?? '';
                _username = data['username'] ?? '';
              });
            } else {
              setState(() { _errorMessage = "User not found."; });
            }
          } else {
            setState(() { _errorMessage = "User not found."; });
          }
        }
      } catch (e) {
        print("Error loading user data: $e");
        if (mounted) setState(() { _errorMessage = "Error loading data."; });
      } finally {
        if (mounted) setState(() { _isLoading = false; });
      }
    } else {
      if (mounted) setState(() { _errorMessage = "Not logged in."; _isLoading = false; });
    }
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
    final linkStyle = TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark);
    final borderRadius = BorderRadius.circular(12.0);

    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF1B255), borderRadius: borderRadius),
      child: ClipRRect(
        borderRadius: borderRadius,
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
                                  // Email is private unless it's MY profile
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

                            // Edit Controls: Only show if this is MY profile
                            if (_isMyProfile)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Restored "View Profile" link as requested
                                  RichText(
                                    text: TextSpan(
                                      text: 'view profile',
                                      style: linkStyle,
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FanzinePage())),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  RichText(
                                    text: TextSpan(
                                      text: 'edit info',
                                      style: linkStyle,
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (context) => const EditInfoPage())),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  RichText(
                                    text: TextSpan(
                                      text: 'upload image',
                                      style: linkStyle,
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          if (currentUser?.uid == null) return;
                                          final userId = currentUser!.uid;
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (BuildContext dialogContext) => ImageUploadModal(userId: userId),
                                          );
                                        },
                                    ),
                                  ),
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
                    // --- EDITOR TAB (0) ---
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
                    // --- FANZINES TAB (1) ---
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
                    // --- PAGES TAB (2) ---
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