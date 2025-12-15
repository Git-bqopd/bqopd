import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:flutter/material.dart';
// Import the widget for the top section
import '../widgets/edit_info_widget.dart';

class EditInfoPage extends StatelessWidget {
  const EditInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: true, // The page handles the scrolling now
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: const EditInfoWidget(),
          ),
        ),
      ),
    );
  }
}