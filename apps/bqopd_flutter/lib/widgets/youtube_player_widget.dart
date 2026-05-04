import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A widget that fetches a YouTube ID from a Firestore image document
/// and renders an iframe player.
class YouTubePlayerWidget extends StatefulWidget {
  final String imageId;

  const YouTubePlayerWidget({super.key, required this.imageId});

  @override
  State<YouTubePlayerWidget> createState() => _YouTubePlayerWidgetState();
}

class _YouTubePlayerWidgetState extends State<YouTubePlayerWidget> {
  YoutubePlayerController? _controller;
  bool _isLoading = true;
  String? _youtubeId;
  // Use a unique key that we regenerate to force total destruction of the player
  Key _playerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _fetchAndInit();
  }

  @override
  void didUpdateWidget(covariant YouTubePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the imageId changed, we MUST reset everything
    if (oldWidget.imageId != widget.imageId) {
      _fetchAndInit();
    }
  }

  Future<void> _fetchAndInit() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _youtubeId = null;
      // Force a new key to ensure the previous iframe is destroyed
      _playerKey = UniqueKey();

      // Explicitly close and nullify the controller
      if (_controller != null) {
        _controller!.close();
        _controller = null;
      }
    });

    try {
      // Use a fresh fetch to ensure we aren't getting cached old IDs
      final doc = await FirebaseFirestore.instance
          .collection('images')
          .doc(widget.imageId)
          .get(const GetOptions(source: Source.serverAndCache));

      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        final newYoutubeId = data['youtubeId'] as String?;

        if (newYoutubeId != null && newYoutubeId.isNotEmpty) {
          // Initialize a completely new controller instance
          final controller = YoutubePlayerController.fromVideoId(
            videoId: newYoutubeId,
            autoPlay: false,
            params: const YoutubePlayerParams(
              showControls: true,
              mute: false,
              showFullscreenButton: true,
              loop: false,
              strictRelatedVideos: true,
            ),
          );

          if (mounted) {
            setState(() {
              _youtubeId = newYoutubeId;
              _controller = controller;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching youtubeId for image ${widget.imageId}: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While loading or if we have no ID/Controller, show placeholders
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(64.0),
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_controller == null || _youtubeId == null) {
      return Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text(
              "VIDEO UNAVAILABLE",
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold
              ),
            ),
          ],
        ),
      );
    }

    // Wrap in a Keyed AspectRatio to ensure the framework sees this as a new widget
    return AspectRatio(
      key: _playerKey,
      aspectRatio: 16 / 9,
      child: YoutubePlayer(
        controller: _controller!,
      ),
    );
  }
}