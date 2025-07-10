import 'dart:typed_data';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p; // For path manipulation
import 'package:bqopd/utils/shortcode_generator.dart'; // Added for shortcode generation

class ImageUploadModal extends StatefulWidget {
  final String userId;

  const ImageUploadModal({
    super.key,
    required this.userId,
  });

  @override
  State<ImageUploadModal> createState() => _ImageUploadModalState();
}

class _ImageUploadModalState extends State<ImageUploadModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  PlatformFile? _pickedFile;
  Uint8List? _pickedFileBytes; // For displaying web image preview
  bool _isLoading = false;

  Future<void> _pickImage() async {
    if (_isLoading) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: kIsWeb, // Read file bytes on web for preview & upload
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pickedFile = result.files.first;
          if (kIsWeb && result.files.first.bytes != null) {
            _pickedFileBytes = result.files.first.bytes;
          } else {
            _pickedFileBytes = null; // Reset if not web or no bytes
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No image selected.')),
          );
        }
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (_isLoading) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image.')),
      );
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final String title = _titleController.text;
      final String description = _descriptionController.text;
      final String fileName = _pickedFile!.name;
      final String filePath = 'uploads/${widget.userId}/$fileName';

      // 1. Upload to Firebase Storage
      UploadTask uploadTask;
      final Reference storageRef = FirebaseStorage.instance.ref().child(filePath);

      if (kIsWeb && _pickedFile!.bytes != null) {
        // Web: Upload bytes
        uploadTask = storageRef.putData(_pickedFile!.bytes!, SettableMetadata(contentType: 'image/${p.extension(fileName).substring(1)}'));
      } else if (_pickedFile!.path != null) {
        // Mobile: Upload file from path (not used in this web-focused request but good for completeness)
        // import 'dart:io'; // Required for File
        // uploadTask = storageRef.putFile(File(_pickedFile!.path!));
        throw UnsupportedError("File path based upload is not supported in this web-only implementation.");
      } else {
        throw Exception("Cannot determine upload source (no bytes or path).");
      }

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      // 2. Generate Document ID for the new image
      final newImageRef = FirebaseFirestore.instance.collection('images').doc();
      final String imageId = newImageRef.id;

      // 3. Assign Shortcode
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final String? shortcode = await assignShortcode(firestore, 'image', imageId);

      if (shortcode == null) {
        // Halt process if shortcode generation fails
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate a unique shortcode. Please try again.')),
          );
        }
        // Optionally, delete the uploaded file from storage if shortcode assignment is critical
        // await storageRef.delete();
        // print('Uploaded file deleted due to shortcode assignment failure.');
        setState(() { _isLoading = false; });
        return; // Stop execution
      }

      // 4. Store metadata in Firestore, including the shortcode
      await newImageRef.set({
        'title': title,
        'description': description,
        'fileUrl': downloadUrl,
        'uploaderId': widget.userId,
        'fileName': fileName,
        'shortcode': shortcode, // Added shortcode
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image uploaded successfully! Shortcode: $shortcode')),
        );
        Navigator.of(context).pop(true); // Pop with a success indicator
      }

    } catch (e) {
      print("Error uploading image or assigning shortcode: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
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
    return AlertDialog(
      title: const Text('Upload Image'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_isLoading) ...[
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Pick Image'),
                ),
                const SizedBox(height: 10),
                if (_pickedFile != null) ...[
                  Text('Selected: ${_pickedFile!.name}'),
                  if (kIsWeb && _pickedFileBytes != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Image.memory(_pickedFileBytes!, height: 100, width: 100, fit: BoxFit.cover),
                    ),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (!_isLoading)
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        if (!_isLoading)
          ElevatedButton(
            onPressed: _handleSubmit,
            child: const Text('Submit'),
          ),
      ],
    );
  }
}
