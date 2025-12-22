import 'package:flutter/material.dart';
import '../widgets/curator_workbench_widget.dart';

class CuratorWorkbenchPage extends StatelessWidget {
  final String fanzineId;

  const CuratorWorkbenchPage({super.key, required this.fanzineId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Canvas-like feel
      appBar: AppBar(
        title: const Text('Curator Workbench'),
        elevation: 1,
      ),
      body: SafeArea(
        child: CuratorWorkbenchWidget(fanzineId: fanzineId),
      ),
    );
  }
}