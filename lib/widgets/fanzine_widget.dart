import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'login_widget.dart';

class FanzineWidget extends StatefulWidget {
  final String? fanzineShortCode;

  const FanzineWidget({super.key, this.fanzineShortCode});

  @override
  State<FanzineWidget> createState() => _FanzineWidgetState();
}

class _FanzineWidgetState extends State<FanzineWidget> {
  User? get currentUser => FirebaseAuth.instance.currentUser;

  final PageController _pageController = PageController();
  int _currentPage = 0;

  String _displayUrl = 'bqopd.com/...';
  String? _targetShortCode;
  bool _isLoadingData = true;
  bool _showLoginLink = false;

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
      await _loadPublicFanzine(widget.fanzineShortCode!);
    } else {
      await _loadDashboard();
    }

    if (mounted) setState(() { _isLoadingData = false; });
  }

  Future<void> _loadPublicFanzine(String shortCode) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('fanzines')
          .where('shortCode', isEqualTo: shortCode)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _displayUrl = 'bqopd.com/404';
        return;
      }

      if (currentUser == null) {
        _displayUrl = 'Login or Register';
        _showLoginLink = true;
        _targetShortCode = null;
      } else {
        _showLoginLink = false;
        try {
          final userDoc = await FirebaseFirestore.instance.collection('Users').doc(currentUser!.uid).get();
          if (userDoc.exists) {
            final myUsername = userDoc.data()?['username'] ?? 'user';
            _displayUrl = 'bqopd.com/$myUsername';
            _targetShortCode = myUsername; // Target my username
          } else {
            _displayUrl = 'bqopd.com/user';
            _targetShortCode = null;
          }
        } catch (e) {
          _displayUrl = 'bqopd.com/home';
          _targetShortCode = null;
        }
      }

      _pages = [
        const Center(child: Text('Indicia (Public View)')),
        const Center(child: Text('Creators (Public View)')),
        const Center(child: Text('Stats (Public View)')),
      ];

    } catch (e) {
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
          _targetShortCode = username; // Target my username
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
    } else if (_targetShortCode != null) {
      // NAVIGATE TO VANITY URL
      context.goNamed(
        'shortlink',
        pathParameters: {'code': _targetShortCode!},
      );
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
    // Removed rounded corners (radius set to 0.0 effectively removes rounding)
    // const borderRadius = BorderRadius.zero;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF1B255),
        // borderRadius: borderRadius, // Removed
      ),
      child: Padding( // Removed ClipRRect as it's not needed without rounded corners
        padding: const EdgeInsets.all(16.0),
        child: _isLoadingData
            ? const Center(child: CircularProgressIndicator())
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RichText(
                text: TextSpan(
                  text: _displayUrl,
                  style: linkStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = _handleLinkTap,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 1, color: Colors.black54),
            const SizedBox(height: 20),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTab('indicia', 0),
                  _buildTabSeparator(),
                  _buildTab('creators', 1),
                  _buildTabSeparator(),
                  _buildTab('stats', 2),
                ],
              ),
            ),
            const SizedBox(height: 10),
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