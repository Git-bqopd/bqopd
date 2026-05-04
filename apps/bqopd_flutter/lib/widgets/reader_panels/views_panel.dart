import 'package:flutter/material.dart';
import '../stats_table.dart';
import 'package:bqopd_core/bqopd_core.dart';

class ViewsPanel extends StatelessWidget {
  final String imageId;
  final ViewService viewService;

  const ViewsPanel({
    super.key,
    required this.imageId,
    required this.viewService,
  });

  @override
  Widget build(BuildContext context) {
    if (imageId.isEmpty) {
      return const Text(
        "Image not yet registered. Wait for OCR.",
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }
    return StatsTable(contentId: imageId, viewService: viewService);
  }
}