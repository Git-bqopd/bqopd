import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FullPageImageViewer extends StatelessWidget {
  final String imageUrl;

  const FullPageImageViewer({
    super.key,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[800],
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
                ),
              ),
            ),
          ),
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
                  icon: Icons.share,
                  platformName: "Twitter",
                ),
                _buildSocialIconButton(
                  context,
                  icon: Icons.camera_alt_outlined,
                  platformName: "Instagram",
                ),
                _buildSocialIconButton(
                  context,
                  icon: Icons.link,
                  platformName: "Copy Link",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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