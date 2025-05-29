import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Assuming components are in lib/components
import '../components/button.dart';
import '../components/textfield.dart';

class CreateFanzinePage extends StatefulWidget {
  const CreateFanzinePage({super.key});

  @override
  State<CreateFanzinePage> createState() => _CreateFanzinePageState();
}

class _CreateFanzinePageState extends State<CreateFanzinePage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false; // For loading indicator

  Future<void> _pickImages() async {
    if (_isLoading) return; // Prevent picking if already uploading
    final List<XFile> pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedImages = pickedFiles;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool canProceed = _selectedImages.isNotEmpty && _titleController.text.isNotEmpty && !_isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Create New Fanzine"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack( // Wrap with Stack for loading indicator
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Image Selection Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.image_search),
                  label: const Text("Select Fanzine Pages (Images)"),
                  onPressed: _pickImages,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Image Previews
            _selectedImages.isEmpty
                ? Container(
                    height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text("No images selected.", style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : SizedBox(
                    height: 150, // Adjust height as needed
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_selectedImages[index].path),
                              width: 100,
                              height: 150,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            const SizedBox(height: 24),

            // Title TextField
            const Text("Title", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            MyTextField( // Using MyTextField from components
              controller: _titleController,
              hintText: "Enter fanzine title",
              obscureText: false,
              onChanged: (_) => setState(() {}), // To update button state
            ),
            const SizedBox(height: 16),

            // Description TextField
            const Text("Description", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            MyTextField( // Using MyTextField from components
              controller: _descriptionController,
              hintText: "Enter fanzine description (optional)",
              obscureText: false,
              maxLines: 5, // For multiline input
            ),
            const SizedBox(height: 32),

            // Next Button
            MyButton( // Using MyButton from components
              onTap: canProceed ? _uploadFanzine : null, // Button is disabled if cannot proceed or is loading
              text: "Create Fanzine",
            ),
          ],
        ),
      ),
      // Loading Indicator Overlay
      if (_isLoading)
        Container(
          color: Colors.black.withOpacity(0.5),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ],
    ),
    );
  }

  Future<void> _uploadFanzine() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Not logged in. Please log in and try again.')),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final String fanzineID = FirebaseFirestore.instance.collection('fanzines').doc().id;
    List<String> pageImageURLs = [];
    String coverImageURL = '';

    try {
      // 1. Upload Images to Firebase Storage
      for (int i = 0; i < _selectedImages.length; i++) {
        XFile imageFile = _selectedImages[i];
        File file = File(imageFile.path);
        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
        String filePath = 'users/${currentUser.uid}/fanzines/$fanzineID/$fileName';

        UploadTask uploadTask = FirebaseStorage.instance.ref(filePath).putFile(file);
        TaskSnapshot snapshot = await uploadTask;
        String downloadURL = await snapshot.ref.getDownloadURL();
        pageImageURLs.add(downloadURL);

        if (i == 0) { // Designate the first image as cover
          coverImageURL = downloadURL;
        }
      }

      if (pageImageURLs.isEmpty) {
        throw Exception("No images were successfully uploaded.");
      }
      if (coverImageURL.isEmpty && pageImageURLs.isNotEmpty) {
        coverImageURL = pageImageURLs.first; // Fallback if first wasn't set
      }


      // 2. Create Firestore Document
      Map<String, dynamic> fanzineData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'authorID': currentUser.uid,
        'authorName': currentUser.displayName ?? currentUser.email ?? 'Anonymous', // Use display name, fallback to email or 'Anonymous'
        'coverImageURL': coverImageURL,
        'pages': pageImageURLs,
        'pageCount': pageImageURLs.length,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isPublished': true, // Default to published
      };

      await FirebaseFirestore.instance.collection('fanzines').doc(fanzineID).set(fanzineData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fanzine created successfully!')),
        );
        // Clear fields and selected images
        _titleController.clear();
        _descriptionController.clear();
        setState(() {
          _selectedImages = [];
        });
        Navigator.of(context).pop(); // Go back to the previous page
      }

    } catch (e) {
      print("Error creating fanzine: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create fanzine: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
