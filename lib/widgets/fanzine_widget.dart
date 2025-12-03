import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../pages/profile_page.dart';

class FanzineWidget extends StatefulWidget {
  const FanzineWidget({super.key});

  @override
  State<FanzineWidget> createState() => _FanzineWidgetState();
}

class _FanzineWidgetState extends State<FanzineWidget> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  String _displayUrl = 'bqopd.com/...'; // Default placeholder
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() { _isLoadingData = true; });

    if (currentUser != null) {
      try {
        // 1. Try fetching from the new UID document first
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser!.uid)
            .get();

        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          final username = data['username'] as String?;

          setState(() {
            if (username != null && username.isNotEmpty) {
              _displayUrl = 'bqopd.com/$username';
            } else {
              _displayUrl = 'bqopd.com/user'; // Fallback if username missing
            }
          });
        } else {
          // Fallback: Try legacy email doc if UID doc is missing
          final emailDoc = await FirebaseFirestore.instance
              .collection('Users')
              .doc(currentUser!.email)
              .get();

          if (emailDoc.exists && mounted) {
            final data = emailDoc.data() as Map<String, dynamic>;
            final username = data['username'] as String?;
            setState(() {
              if (username != null && username.isNotEmpty) {
                _displayUrl = 'bqopd.com/$username';
              }
            });
          }
        }
      } catch (e) {
        print("Error loading username: $e");
      } finally {
        if (mounted) setState(() { _isLoadingData = false; });
      }
    } else {
      if (mounted) setState(() { _isLoadingData = false; });
    }
  }

  void goToProfilePage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfilePage()),
    );
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
              // --- Top Row: Profile Link (Updated) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center, // Centered
                children: [
                  RichText(
                    text: TextSpan(
                      text: _displayUrl,
                      style: linkStyle,
                      recognizer: TapGestureRecognizer()
                        ..onTap = goToProfilePage,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              // Single pixel horizontal line
              const Divider(
                height: 1,
                thickness: 1,
                color: Colors.black54, // Matches the '|' separators below
              ),
              const SizedBox(height: 20),

              // --- Second Row: Tab Navigation ---
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

              // --- Third Row: PageView ---
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  children: const [
                    Center(child: Text('This is the indicia page.')),
                    Center(child: Text('This is the creators page.')),
                    Center(child: Text('This is the stats page.')),
                  ],
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