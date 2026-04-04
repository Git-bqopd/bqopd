import 'package:flutter/material.dart';
import '../youtube_player_widget.dart';

class YoutubePanel extends StatelessWidget {
  final String imageId;

  const YoutubePanel({super.key, required this.imageId});

  @override
  Widget build(BuildContext context) {
    return YouTubePlayerWidget(imageId: imageId);
  }
}