import 'package:flutter/material.dart';
// Removed: import 'package:share_plus/share_plus.dart';

class FullPageImageViewer extends StatelessWidget {
  final String imageUrl;
  // final List<String>? allImageUrls; // For potential swipe navigation later
  // final int initialIndex; // If allImageUrls is used

  const FullPageImageViewer({
    super.key,
    required this.imageUrl,
    // this.allImageUrls,
    // this.initialIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background for image viewing
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        elevation: 0, // No shadow
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        // Optional: Title if needed, or keep it minimal
        // title: const Text("View Page", style: TextStyle(color: Colors.white)),
      ),
      body: Column( // Changed Center to Column
        children: [
          Expanded( // InteractiveViewer takes up available space
            child: InteractiveViewer(
              panEnabled: true, // Enable panning
              minScale: 0.5,    // Minimum scale factor
          maxScale: 4.0,    // Maximum scale factor
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain, // Ensure the whole image is visible, can be zoomed
            loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white), // Spinner color on dark background
                ),
              );
            },
            errorWidget: (BuildContext context, Object error, StackTrace? stackTrace) {
              print("Error loading full-page image $imageUrl: $error");
              return Container(
                color: Colors.grey[800], // Darker grey for error on black background
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 60),
                      SizedBox(height: 10),
                      Text(
                        "Error loading image",
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
          ),
          // Social Share Icons Row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _buildSocialIconButton(
                  context,
                  icon: Icons.facebook,
                  platformName: "Facebook",
                ),
                _buildSocialIconButton(
                  context,
                  icon: Icons.share, // Generic share, can represent Twitter or others
                  platformName: "Twitter", // Example name
                ),
                _buildSocialIconButton(
                  context,
                  icon: Icons.camera_alt_outlined, // Placeholder for Instagram-like
                  platformName: "Instagram",
                ),
                _buildSocialIconButton(
                  context,
                  icon: Icons.link, // Placeholder for copying link
                  platformName: "Copy Link",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build social icon buttons
  Widget _buildSocialIconButton(BuildContext context, {required IconData icon, required String platformName}) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      iconSize: 30.0,
      tooltip: 'Share to $platformName',
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share to $platformName tapped (not implemented).'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}
