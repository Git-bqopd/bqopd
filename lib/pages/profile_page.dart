import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Import the widget for the top section
import '../widgets/profile_widget.dart'; // Adjust path if needed

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null || currentUser.email == null) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: const Center(
          child: Text('Please log in to see your images.'),
        ),
      );
    }

    final userEmail = currentUser.email!;

    return Scaffold(
      backgroundColor: Colors.grey[200], // Match other pages background
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
            children: [
              // --- Top Section (Profile Info) ---
              Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
                child: AspectRatio(
                  aspectRatio: 8 / 5, // Wide aspect ratio
                  child: MyInfoWidget(), // Embed the info widget
                ),
              ),

              // --- Bottom Section (Uploads Grid) ---
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('images')
                      .where('uploaderId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                      .orderBy('timestamp', descending: true) // Optional: order by timestamp
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      print('🔥 Firestore error: ${snapshot.error}');
                      return Text('Something went wrong');                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text("No images uploaded yet."));
                    }

                    final images = snapshot.data!.docs;

                    print('🖼️ Found ${images.length} images');
                    for (var doc in images) {
                      final data = doc.data() as Map<String, dynamic>?;
                      print('📷 ${data?['fileUrl']}');
                    }

                    return GridView.count(
                      crossAxisCount: 3, // Three columns
                      childAspectRatio: 5 / 8, // Aspect ratio for grid items (width/height)
                      mainAxisSpacing: 8.0,
                      crossAxisSpacing: 8.0,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: images.map((doc) {
                        final data = doc.data() as Map<String, dynamic>?;
                        final imageUrl = data?['fileUrl'] as String?;
                        // final title = data['title'] as String? ?? 'Untitled'; // If you want to display title

                        if (imageUrl == null || imageUrl.isEmpty) {
                          // Handle missing or empty URL, perhaps show a placeholder or an error icon
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(child: Icon(Icons.broken_image, color: Colors.white)),
                          );
                        }

                        print('📸 Attempting to load: $imageUrl');

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12.0), // Apply rounding to image
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover, // Cover the container
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
                              print('❌ Image failed to load: $imageUrl');
                              print('⚠️ Exception: $exception');
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
