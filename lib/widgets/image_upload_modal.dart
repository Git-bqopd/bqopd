import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;

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

  XFile? _pickedFile;
  Uint8List? _pickedFileBytes;
  bool _isUploading = false;

  Future<void> _pickImage() async {
    if (_isUploading) return;
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pickedFile = image;
          _pickedFileBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (_isUploading) return;

    if (!_formKey.currentState!.validate()) return;
    if (_pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image.')),
      );
      return;
    }

    setState(() { _isUploading = true; });

    try {
      final String title = _titleController.text;
      final String description = _descriptionController.text;
      final String fileName = _pickedFile!.name;
      final String filePath = 'uploads/${widget.userId}/$fileName';

      // 1. Upload to Storage
      final Reference storageRef = FirebaseStorage.instance.ref().child(filePath);
      final fileData = await _pickedFile!.readAsBytes();

      final uploadTask = storageRef.putData(
        fileData,
        SettableMetadata(contentType: 'image/${p.extension(fileName).replaceAll('.', '')}'),
      );

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      // 2. Save to Firestore
      // We don't need to pre-generate an ID or a shortcode.
      // We just let Firestore generate the ID (.doc())
      final newImageRef = FirebaseFirestore.instance.collection('images').doc();

      await newImageRef.set({
        'title': title,
        'description': description,
        'fileUrl': downloadUrl,
        'uploaderId': widget.userId,
        'fileName': fileName,
        // We use the Document ID as the reference code if needed internally,
        // or just the filename. We DO NOT use the global shortcode generator.
        'internalRef': newImageRef.id,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image uploaded successfully!')),
        );
        Navigator.of(context).pop(true);
      }

    } catch (e) {
      print("Error uploading image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isUploading = false; });
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
              if (_isUploading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(child: CircularProgressIndicator()),
                ),

              if (!_isUploading) ...[
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Pick Image'),
                ),
                const SizedBox(height: 10),
                if (_pickedFile != null) ...[
                  Text('Selected: ${_pickedFile!.name}'),
                  if (_pickedFileBytes != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                            _pickedFileBytes!,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.isEmpty ? 'Please enter a title' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (value) => value == null || value.isEmpty ? 'Please enter a description' : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (!_isUploading)
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        if (!_isUploading)
          ElevatedButton(
            onPressed: _handleSubmit,
            child: const Text('Submit'),
          ),
      ],
    );
  }
}