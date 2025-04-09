import 'package:flutter/material.dart';
// Import the widget for the top section
import '../widgets/edit_info_widget.dart'; // Adjust path if needed

class EditInfoPage extends StatelessWidget {
  const EditInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    // This structure is nearly identical to my_info_page_code_v2
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: SingleChildScrollView( // Make page scrollable
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Top Section (Edit Form) ---
              Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0), // LTR padding, no B
                child: AspectRatio(
                  aspectRatio: 8 / 5, // Wide aspect ratio
                  child: EditInfoWidget(), // Embed the edit widget
                ),
              ),

              // --- Bottom Section (Placeholders Grid) ---
              Padding(
                padding: const EdgeInsets.all(8.0), // All-around padding for grid
                child: GridView.count(
                  crossAxisCount: 3, // Three columns
                  childAspectRatio: 5 / 8, // Aspect ratio for grid items
                  mainAxisSpacing: 8.0,
                  crossAxisSpacing: 8.0,
                  shrinkWrap: true, // Needed inside SingleChildScrollView
                  physics: const NeverScrollableScrollPhysics(), // Needed inside SingleChildScrollView
                  children: List.generate(12, (index) { // Example placeholders
                    final colors = [Colors.blueGrey, Colors.teal, Colors.amber, Colors.deepOrange, Colors.purple, Colors.indigo];
                    final color = colors[index % colors.length];
                    // Using the same helper function
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

  // --- Helper widget for COLOR placeholders (copied from MyInfoPage) ---
  // Consider moving this to a shared utility file if used in many places
  Widget _buildColorPlaceholder(Color color, String text) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
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
