import 'package:flutter/material.dart';
import 'package:bqopd/widgets/page_wrapper.dart';
import '../widgets/new_fanzine_reader.dart';
import '../widgets/fanzine_widget.dart'; // Reusing existing header widget

class NewReaderPage extends StatelessWidget {
  final String fanzineId;

  const NewReaderPage({
    super.key,
    required this.fanzineId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: false, // The reader list handles scrolling
          child: NewFanzineReader(
            fanzineId: fanzineId,
            // Reusing FanzineWidget as header, assuming we want the "Cover/Dashboard" look at top
            headerWidget: const FanzineWidget(),
          ),
        ),
      ),
    );
  }
}