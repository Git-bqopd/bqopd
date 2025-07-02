import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Import the widget for the top section
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
        childAspectRatio: 5 / 8, // Corrected aspect ratio: Taller than wide
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
      ),
      itemCount: 6, // Display 6 placeholders
      itemBuilder: (context, index) {
        // The AspectRatio widget for each item is now driven by the gridDelegate's childAspectRatio
        // So, we don't strictly need another AspectRatio widget here if the Container respects it.
        // However, to be absolutely explicit and ensure it, we can keep it or rely on the delegate.
        // For simplicity and consistency with how GridView.count works, let's rely on childAspectRatio
        // in the delegate and ensure the Container fills its allocated space.
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey[300], // Light gray color
              borderRadius: BorderRadius.circular(12.0), // Match image rounding
            ),
            // You could add a child here if you want text or an icon inside the placeholder
            // child: Center(child: Text('Fanzine ${index + 1}')),
          ),
        );
      },
      // The padding for the GridView itself is handled by the Padding widget wrapping the PageView
    );
  }

  Widget _buildPagesView() {
    // This is the existing StreamBuilder logic for displaying images
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
          print('🔥 Firestore error: ${snapshot.error}');
          return const Center(child: Text('Something went wrong loading images.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No images uploaded yet."));
        }

        final images = snapshot.data!.docs;

        // print('🖼️ Found ${images.length} images for Pages view'); // Debug log

        return GridView.count(
          crossAxisCount: 3, // Three columns
          childAspectRatio: 5 / 8, // Aspect ratio for grid items (width/height)
          mainAxisSpacing: 8.0,
          crossAxisSpacing: 8.0,
          // shrinkWrap: true, // Not needed here as PageView handles scroll
          // physics: const NeverScrollableScrollPhysics(), // Not needed here
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

            // print('📸 Pages view: Attempting to load: $imageUrl'); // Debug log

            return ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
                  // print('❌ Pages view: Image failed to load: $imageUrl'); // Debug log
                  // print('⚠️ Pages view: Exception: $exception'); // Debug log
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

    // final userEmail = currentUser.email!; // Not directly used in this structure anymore, but good to keep if needed later

    return Scaffold(
      backgroundColor: Colors.grey[200], // Match other pages background
      body: SafeArea(
        // Removed SingleChildScrollView as PageView handles scrolling for its content
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
          children: [
            // --- Top Section (Profile Info) ---
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
              child: AspectRatio(
                aspectRatio: 8 / 5, // Wide aspect ratio
                // Use ProfileWidget and pass the required parameters
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

            // --- Bottom Section (PageView for Fanzines/Uploads Grid) ---
            Expanded( // PageView needs to be in an Expanded widget if inside a Column
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: PageView(
                  controller: _pageController,
                  children: [
                    _buildFanzinesView(), // To be implemented
                    _buildPagesView(), // To be implemented (will contain the StreamBuilder and GridView)
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
