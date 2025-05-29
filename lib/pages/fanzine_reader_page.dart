import 'dart:math' as Math; // Added for Math.min
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'full_page_image_viewer.dart'; // Import the new viewer

class FanzineReaderPage extends StatefulWidget {
  final String fanzineID;
  final String fanzineTitle;

  const FanzineReaderPage({
    super.key,
    required this.fanzineID,
    required this.fanzineTitle,
  });

  @override
  State<FanzineReaderPage> createState() => _FanzineReaderPageState();
}

// Special constant to identify the author details placeholder in the grid
const String _authorDetailsPlaceholder = "##AUTHOR_DETAILS_PLACEHOLDER##";

class _FanzineReaderPageState extends State<FanzineReaderPage> {
  DocumentSnapshot? _fanzineDoc;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchFanzineDetails();
  }

  Future<void> _fetchFanzineDetails() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(widget.fanzineID)
          .get();

      if (mounted) {
        if (doc.exists) {
          setState(() {
            _fanzineDoc = doc;
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = "Fanzine not found.";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error fetching fanzine details: $e");
      if (mounted) {
        setState(() {
          _error = "Failed to load fanzine: ${e.toString()}";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fanzineTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const CircularProgressIndicator();
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.red, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_fanzineDoc == null || !_fanzineDoc!.exists) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          "Fanzine not found.",
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Fanzine data is available
    final data = _fanzineDoc!.data() as Map<String, dynamic>?; // Safe cast
    if (data == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          "Fanzine data is corrupt or unavailable.",
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }


    final String? coverImageUrl = data['coverImageURL'] as String?;
    final List<String> pageImageUrls = (data['pages'] as List<dynamic>?)
        ?.map((item) => item.toString())
        ?.where((url) => url.isNotEmpty) // Filter out empty URLs
        ?.toList() ?? [];

    List<String> gridItems = [];
    gridItems.add(_authorDetailsPlaceholder); // Item 0: Author details placeholder

    if (coverImageUrl != null && coverImageUrl.isNotEmpty) {
      gridItems.add(coverImageUrl); // Item 1: Cover image
    }

    gridItems.addAll(pageImageUrls); // Items 2 onwards: Actual pages

    if (gridItems.length == 1 && gridItems[0] == _authorDetailsPlaceholder && (coverImageUrl == null || coverImageUrl.isEmpty) && pageImageUrls.isEmpty) {
      // Only placeholder exists because there's no cover and no pages
      return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Fanzine Details", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text("Title: ${widget.fanzineTitle}", style: Theme.of(context).textTheme.titleMedium),
            Text("ID: ${widget.fanzineID}", style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            const Center(child: Text("This fanzine has no cover image or pages to display.", textAlign: TextAlign.center,)),
          ],
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
        childAspectRatio: 0.70, // Adjusted for a taller item, typical for book covers/pages
      ),
      itemCount: gridItems.length,
      itemBuilder: (context, index) {
        final item = gridItems[index];

        if (item == _authorDetailsPlaceholder) {
          // Index 0: Author Details/Info Widget Placeholder
          return Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey[400]!, width: 1),
            ),
            child: Center(
              child: Text(
                "Author Details / Info Widget (Placeholder)",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        } else {
          // Other items: Images (cover or page)
          final imageUrl = item;
          return InkWell(
            onTap: () {
              // final fanzineData = _fanzineDoc?.data() as Map<String, dynamic>?;
              // final String authorName = fanzineData?['authorName'] as String? ?? 'Unknown Author';

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FullPageImageViewer(
                    imageUrl: imageUrl,
                    // fanzineTitle: widget.fanzineTitle, // Reverted
                    // fanzineAuthorName: authorName, // Reverted
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                  print("Error loading image $imageUrl: $error");
                  return Container(
                    decoration: BoxDecoration(
                       color: Colors.grey[200],
                       borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Center(
                      child: Icon(Icons.broken_image_rounded, color: Colors.grey[500], size: 40),
                    ),
                  );
                },
              ),
            ),
          );
        }
      },
    );
  }
}
