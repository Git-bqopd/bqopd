import 'package:flutter/material.dart';
// Import the widget for the top section
import '../widgets/my_info_widget.dart'; // Adjust path if needed

class MyInfoPage extends StatelessWidget {
  const MyInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --- AppBar REMOVED ---
      // appBar: AppBar(
      //   title: const Text('My Info'),
      //   backgroundColor: Colors.grey[300],
      //   elevation: 0,
      // ),
      backgroundColor: Colors.grey[200], // Match other pages background
      body: SafeArea(
        // Use SingleChildScrollView to make the whole page scrollable
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
            children: [
              // --- Top Section (Profile Info) ---
              // *** ADDED Padding around AspectRatio (Left, Top, Right, NO Bottom) ***
              Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
                child: AspectRatio(
                  aspectRatio: 8 / 5, // Wide aspect ratio
                  // The MyInfoWidget itself will have rounded corners (see next code block)
                  child: MyInfoWidget(), // Embed the info widget
                ),
              ),

              // --- Bottom Section (Uploads Grid) ---
              Padding(
                // Grid already has all-around padding
                padding: const EdgeInsets.all(8.0),
                child: GridView.count(
                  crossAxisCount: 3, // Three columns
                  childAspectRatio: 5 / 8, // Aspect ratio for grid items (width/height)
                  mainAxisSpacing: 8.0,
                  crossAxisSpacing: 8.0,
                  // Important for nested scrolling:
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: List.generate(12, (index) { // Generate 12 placeholders for example
                    final colors = [Colors.blueGrey, Colors.teal, Colors.amber, Colors.deepOrange, Colors.purple, Colors.indigo];
                    final color = colors[index % colors.length];
                    return _buildColorPlaceholder(color, 'Upload ${index + 1}');
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper widget for COLOR placeholders (redefined here) ---
  Widget _buildColorPlaceholder(Color color, String text) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12), // Consistent rounding
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
