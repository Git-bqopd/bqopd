import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchYoutubeId();
  }

  Future<void> _fetchYoutubeId() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('images').doc(widget.imageId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _youtubeId = data['youtubeId'];
        if (_youtubeId != null && _youtubeId!.isNotEmpty) {
          _controller = YoutubePlayerController.fromVideoId(
            videoId: _youtubeId!,
            autoPlay: false,
            params: const YoutubePlayerParams(
              showControls: true,
              mute: false,
              showFullscreenButton: true,
              loop: false,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error fetching youtubeId: $e");
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24.0),
        child: CircularProgressIndicator(color: Colors.white),
      ));
    }
    if (_controller == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text("Video not found.", style: TextStyle(color: Colors.white)),
      ));
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: YoutubePlayer(
        controller: _controller!,
      ),
    );
  }
}