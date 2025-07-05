import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/profile_widget.dart'; // Adjust path if needed
import '../widgets/new_fanzine_modal.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late PageController _pageController;
  int _currentIndex = 0; // 0 for Fanzines, 1 for Pages

  bool _isEditor = false;
  bool _isLoadingCurrentUser = true;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _pageController.addListener(() {
      if (_pageController.page?.round() != _currentIndex) {
        setState(() {
          _currentIndex = _pageController.page!.round();
        });
      }
    });
    _loadCurrentUserEditorStatus();
  }

  Future<void> _loadCurrentUserEditorStatus() async {
    setState(() {
      _isLoadingCurrentUser = true;
    });
    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser != null && _currentUser!.email != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(_currentUser!.email)
            .get();
        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _isEditor = (data['Editor'] == true); // Default to false if null or not true
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading editor status: ${e.toString()}')),
          );
        }
        print("Error loading user editor status: $e");
      } finally {
        if (mounted) {
          setState(() {
            _isLoadingCurrentUser = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingCurrentUser = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showNewFanzineModal() {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to create a fanzine.')),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false, // User must explicitly cancel or save
      builder: (BuildContext dialogContext) {
        return NewFanzineModal(userId: _currentUser!.uid);
      },
    );
  }

  Widget _buildFanzinesView() {
    if (_isLoadingCurrentUser) {
      return const Center(child: CircularProgressIndicator());
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // Three columns, similar to the images grid
        childAspectRatio: 5 / 8, // Taller than wide
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
      ),
      itemCount: 6, // Display 6 placeholders
      itemBuilder: (context, index) {
        if (index == 0 && _isEditor) {
          return TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.blueAccent, // Example color
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            onPressed: _showNewFanzineModal,
            child: const Text(
              "make new fanzine",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(12.0),
          ),
        );
      },
    );
  }

  Widget _buildPagesView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('images')
          .where('uploaderId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Something went wrong loading images.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No images uploaded yet."));
        }

        final images = snapshot.data!.docs;

        return GridView.count(
          crossAxisCount: 3,
          childAspectRatio: 5 / 8,
          mainAxisSpacing: 8.0,
          crossAxisSpacing: 8.0,
          children: images.map((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            final imageUrl = data?['fileUrl'] as String?;

            if (imageUrl == null || imageUrl.isEmpty) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Icon(Icons.broken_image, color: Colors.white)),
              );
            }

            return ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, exception, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: Icon(Icons.error_outline, color: Colors.red)),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null || currentUser.email == null) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: const Center(
          child: Text('Please log in to see your profile.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
              child: AspectRatio(
                aspectRatio: 8 / 5,
                child: ProfileWidget(
                  currentIndex: _currentIndex,
                  onFanzinesTapped: () {
                    _pageController.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  onPagesTapped: () {
                    _pageController.animateToPage(
                      1,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: PageView(
                  controller: _pageController,
                  children: [
                    _buildFanzinesView(),
                    _buildPagesView(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
