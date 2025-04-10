import 'package:flutter/material.dart';
import '../widgets/login_widget.dart'; // Ensure this path is correct

class LoginPage extends StatelessWidget {
  final void Function()? onTap;

  const LoginPage({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(8.0),
          mainAxisSpacing: 8.0,
          crossAxisSpacing: 8.0,
          childAspectRatio: 5 / 8, // Keep the aspect ratio for all cells
          children: <Widget>[
            // --- Cell 1: Login Widget ---
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0), // Match the container's radius
                child: LoginWidget( // Make sure LoginWidget is imported correctly
                  onTap: onTap,
                ),
              ),
            ),
            _buildImageAssetPlaceholder('assets/THREE - 01.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 02.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 03.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 04.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 05.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 06.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 07.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 08.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 09.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 10.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 11.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 12.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 13.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 14.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 15.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 16.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 17.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 18.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 19.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 20.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 21.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 22.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 23.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 24.jpg'),
            _buildImageAssetPlaceholder('assets/THREE - 25.jpg'),
          ],
        ),
      ),
    );
  }

  // --- NEW Helper widget for IMAGE ASSET placeholders ---
  Widget _buildImageAssetPlaceholder(String imagePath) {
    // This container will be forced into the 5/8 aspect ratio by the GridView
    return Container(
      decoration: BoxDecoration(
        // Optional: Add a background color while the image loads or if it fails
        color: Colors.grey[300], // A light grey background
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect( // Clip the image to the rounded corners
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          imagePath,
          fit: BoxFit.cover, // Cover the container, might crop the image
          // Optional: Add error handling
          errorBuilder: (context, error, stackTrace) {
            print("Error loading asset: $imagePath\n$error");
            return Container( // Fallback placeholder on error
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.red),
                      SizedBox(height: 4),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0),
                        child: Text(
                          "Error",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ));
          },
          // Optional: Add a loading indicator (fade-in effect)
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              return child;
            }
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 500), // Adjust duration as needed
              curve: Curves.easeOut,
              child: child,
            );
          },
        ),
      ),
    );
  }


  // --- RENAMED original Helper widget for COLOR placeholders ---
  Widget _buildColorPlaceholder(Color color, String text) {
    // This container will be forced into the 5/8 aspect ratio by the GridView
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}