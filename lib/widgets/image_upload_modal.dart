import 'package:flutter/foundation.dart';
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
    if (_pickedFile == null || _pickedFileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final String title = _titleController.text;
      final String description = _descriptionController.text;
      final String fileName = _pickedFile!.name;
      final String filePath = 'uploads/${widget.userId}/$fileName';

      // 1. Upload to Storage
      final Reference storageRef =
      FirebaseStorage.instance.ref().child(filePath);

      // Use the bytes we already loaded into memory
      final fileData = _pickedFileBytes!;

      final uploadTask = storageRef.putData(
        fileData,
        SettableMetadata(
            contentType: 'image/${p.extension(fileName).replaceAll('.', '')}'),
      );

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      // 2. Save to Firestore
      final newImageRef = FirebaseFirestore.instance.collection('images').doc();

      await newImageRef.set({
        'title': title,
        'description': description,
        'fileUrl': downloadUrl,
        'uploaderId': widget.userId,
        'fileName': fileName,
        'internalRef': newImageRef.id,
        'timestamp': FieldValue.serverTimestamp(),
        // --- Moderation Fields ---
        'status': 'pending', // Default for moderation queue
        'tags': {}, // Initialize empty tags map for voting
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image uploaded successfully!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint("Error uploading image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
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
    // Using a standard Dialog with explicit constraints avoids the layout race conditions
    // often seen with AlertDialog + Image.memory on Flutter Web.
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Upload Image',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  if (_isUploading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    // Image Preview
                    if (_pickedFileBytes != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _pickedFileBytes!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                  child: Icon(Icons.broken_image,
                                      color: Colors.grey)),
                            ),
                          ),
                        ),
                      ),

                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _pickImage,
                        icon: Icon(_pickedFile == null
                            ? Icons.add_photo_alternate
                            : Icons.change_circle),
                        label: Text(_pickedFile == null
                            ? 'Select Image'
                            : 'Change Image'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade50,
                          foregroundColor: Colors.indigo,
                          elevation: 0,
                        ),
                      ),
                    ),

                    if (_pickedFile != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Center(
                          child: Text(
                            'Selected: ${_pickedFile!.name}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Please enter a title'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 3,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Please enter a description'
                          : null,
                    ),

                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _handleSubmit,
                          child: const Text('Upload'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}