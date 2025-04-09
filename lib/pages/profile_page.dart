import 'package:flutter/material.dart';
import '../widgets/profile_widget.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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
          childAspectRatio: 5 / 8,
          children: <Widget>[
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
                borderRadius: BorderRadius.circular(12.0),
                child: const ProfileWidget(),
              ),
            ),

            _buildImagePlaceholder(Colors.blueGrey, 'Image 1'),
            _buildImagePlaceholder(Colors.teal, 'Image 2'),
            _buildImagePlaceholder(Colors.amber, 'Image 3'),
            _buildImagePlaceholder(Colors.deepOrange, 'Image 4'),
            _buildImagePlaceholder(Colors.purple, 'Image 5'),
          ],
        ),
      ),
    );
  }

  // Helper widget for image placeholders (same as in LoginPage)
  Widget _buildImagePlaceholder(Color color, String text) {
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
