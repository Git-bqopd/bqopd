import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'login_widget.dart'; // Import for the dialog

class FanzineWidget extends StatefulWidget {
  // If provided, we are viewing a specific public fanzine.
  // If null, we are viewing the logged-in user's dashboard (Home).
  final String? fanzineShortCode;

  const FanzineWidget({super.key, this.fanzineShortCode});

  @override
  State<FanzineWidget> createState() => _FanzineWidgetState();
}

class _FanzineWidgetState extends State<FanzineWidget> {
  // FIX: Use a getter so we always get the *current* auth state.
  // If we use 'final User? user = ...' it captures 'null' at creation and never updates after login.
  User? get currentUser => FirebaseAuth.instance.currentUser;

  final PageController _pageController = PageController();
  int _currentPage = 0;

  String _displayUrl = 'bqopd.com/...';
  String? _targetRoute; // Where the link should go
  bool _isLoadingData = true;
  bool _showLoginLink = false; // True if user is NOT logged in and viewing public fanzine

  // Fanzine Data (if public)
  List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant FanzineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fanzineShortCode != widget.fanzineShortCode) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _isLoadingData = true; });

    if (widget.fanzineShortCode != null) {
      // --- PUBLIC MODE: Viewing a specific Fanzine ---
      await _loadPublicFanzine(widget.fanzineShortCode!);
    } else {
      // --- DASHBOARD MODE: Viewing Logged-in User's Home ---
      await _loadDashboard();
    }

    if (mounted) setState(() { _isLoadingData = false; });
  }

  Future<void> _loadPublicFanzine(String shortCode) async {
    try {
      // 1. Find the fanzine doc
      final query = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('shortCode', isEqualTo: shortCode)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _displayUrl = 'bqopd.com/404';
        return;
      }

      final fanzineDoc = query.docs.first;
      final data = fanzineDoc.data();
      final creatorId = data['editorId'] as String?;

      // 2. Determine Link Behavior
      // Use the getter 'currentUser' to check live status
      if (currentUser == null) {
        // Not logged in -> Show Login CTA
        _displayUrl = 'Login or Register';
        _showLoginLink = true;
        _targetRoute = null; // We'll handle tap differently
      } else {
        // Logged in -> Show Creator's Profile Link
        _showLoginLink = false;

        // Per your request: Show the LOGGED IN USER'S vanity URL as a "Home Button"
        // even if viewing someone else's fanzine.
        try {
          final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.uid).get();
          if (userDoc.exists) {
            final myUsername = userDoc.data()?['username'] ?? 'user';
            _displayUrl = 'bqopd.com/$myUsername';
            _targetRoute = '/profile';
          } else {
            _displayUrl = 'bqopd.com/user';
            _targetRoute = '/profile';
          }
        } catch (e) {
          print("Error fetching my username: $e");
          _displayUrl = 'bqopd.com/home';
          _targetRoute = '/profile';
        }
      }

      // 3. Load Pages (Placeholder for now)
      _pages = [
        const Center(child: Text('Indicia (Public View)')),
        const Center(child: Text('Creators (Public View)')),
        const Center(child: Text('Stats (Public View)')),
      ];

    } catch (e) {
      print("Error loading fanzine: $e");
      _displayUrl = 'bqopd.com/error';
    }
  }

  Future<void> _loadDashboard() async {
    if (currentUser == null) {
      _displayUrl = 'bqopd.com';
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser!.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final username = data['username'] as String?;
        if (username != null && username.isNotEmpty) {
          _displayUrl = 'bqopd.com/$username';
          _targetRoute = '/profile'; // Link goes to MY Private Profile Dashboard
        }
      }

      _pages = [
        const Center(child: Text('Your Fanzine Dashboard')),
        const Center(child: Text('Manage Creators')),
        const Center(child: Text('View Stats')),
      ];

    } catch (e) {
      print("Error loading dashboard: $e");
    }
  }

  void _handleLinkTap() {
    if (_showLoginLink) {
      // Show Login Dialog
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            child: LoginWidget(
              onTap: () {
                Navigator.pop(context); // Close dialog if switching to register
                context.go('/register'); // Go to full register page
              },
              // FIX: Handle the successful login!
              onLoginSuccess: () {
                Navigator.pop(context); // 1. Close the modal
                _loadData();            // 2. Refresh this widget (re-checks currentUser getter)
              },
            ),
          ),
        ),
      );
    } else if (_targetRoute != null) {
      if (_targetRoute == '/profile') {
        context.pushNamed('profile');
      } else {
        context.go(_targetRoute!);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).primaryColorDark,
      fontSize: 16,
    );
    final borderRadius = BorderRadius.circular(12.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1B255),
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Top Row: Dynamic Link ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RichText(
                    text: TextSpan(
                      text: _displayUrl,
                      style: linkStyle,
                      recognizer: TapGestureRecognizer()
                        ..onTap = _handleLinkTap,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 1, color: Colors.black54),
              const SizedBox(height: 20),

              // --- Tab Navigation ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTab('indicia', 0),
                  _buildTabSeparator(),
                  _buildTab('creators', 1),
                  _buildTabSeparator(),
                  _buildTab('stats', 2),
                ],
              ),
              const SizedBox(height: 10),

              // --- Content Pages ---
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() { _currentPage = index; });
                  },
                  children: _pages.isEmpty
                      ? [const Center(child: Text("Loading..."))]
                      : _pages,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String text, int index) {
    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: _currentPage == index ? FontWeight.bold : FontWeight.normal,
          color: _currentPage == index ? Colors.black : Colors.black54,
        ),
      ),
    );
  }

  Widget _buildTabSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: Text('|', style: TextStyle(fontSize: 16, color: Colors.black54)),
    );
  }
}