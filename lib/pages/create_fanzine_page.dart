import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  List<Uint8List> _imageBytesList = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickImages() async {
    if (_isLoading) return;
    final List<XFile> pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      List<Uint8List> bytesList = [];
      for (XFile file in pickedFiles) {
        Uint8List bytes = await file.readAsBytes();
        bytesList.add(bytes);
      }
      setState(() {
        _selectedImages = pickedFiles;
        _imageBytesList = bytesList;
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
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ElevatedButton.icon(
                  icon: const Icon(Icons.image_search),
                  label: const Text("Select Fanzine Pages (Images)"),
                  onPressed: _pickImages,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                _imageBytesList.isEmpty
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
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _imageBytesList.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _imageBytesList[index],
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
                const Text("Title", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                MyTextField(
                  controller: _titleController,
                  hintText: "Enter fanzine title",
                  obscureText: false,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                const Text("Description", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                MyTextField(
                  controller: _descriptionController,
                  hintText: "Enter fanzine description (optional)",
                  obscureText: false,
                  maxLines: 5,
                ),
                const SizedBox(height: 32),
                MyButton(
                  onTap: canProceed ? _uploadFanzine : null,
                  text: "Create Fanzine",
                ),
              ],
            ),
          ),
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
      for (int i = 0; i < _selectedImages.length; i++) {
        XFile imageFile = _selectedImages[i];
        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
        String filePath = 'users/${currentUser.uid}/fanzines/$fanzineID/$fileName';

        UploadTask uploadTask = FirebaseStorage.instance.ref(filePath).putData(await imageFile.readAsBytes());
        TaskSnapshot snapshot = await uploadTask;
        String downloadURL = await snapshot.ref.getDownloadURL();
        pageImageURLs.add(downloadURL);

        if (i == 0) {
          coverImageURL = downloadURL;
        }
      }

      if (pageImageURLs.isEmpty) throw Exception("No images were successfully uploaded.");
      if (coverImageURL.isEmpty && pageImageURLs.isNotEmpty) coverImageURL = pageImageURLs.first;

      Map<String, dynamic> fanzineData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'authorID': currentUser.uid,
        'authorName': currentUser.displayName ?? currentUser.email ?? 'Anonymous',
        'coverImageURL': coverImageURL,
        'pages': pageImageURLs,
        'pageCount': pageImageURLs.length,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isPublished': true,
      };

      await FirebaseFirestore.instance.collection('fanzines').doc(fanzineID).set(fanzineData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fanzine created successfully!')),
        );
        _titleController.clear();
        _descriptionController.clear();
        setState(() {
          _selectedImages = [];
          _imageBytesList = [];
        });
        Navigator.of(context).pop();
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
