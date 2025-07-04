import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/profile_widget.dart'; // Adjust path if needed

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late PageController _pageController;
  int _currentIndex = 0; // 0 for Fanzines, 1 for Pages

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
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildFanzinesView() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // Three columns, similar to the images grid
        childAspectRatio: 5 / 8, // Taller than wide
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
      ),
      itemCount: 6, // Display 6 placeholders
      itemBuilder: (context, index) {
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
