import 'dart:typed_data'; // Import for Uint8List
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'html_file_picker.dart'; // Conditional import for file picker

class UploadImageWidget extends StatefulWidget {
  @override
  _UploadImageWidgetState createState() => _UploadImageWidgetState();
}

class _UploadImageWidgetState extends State<UploadImageWidget> {
  XFile? _image;
  Uint8List? _webImage;
  String? _imageUrl;
  String? _errorMessage;

  // Function to pick image from gallery
  Future<void> _pickImage() async {
    try {
      if (kIsWeb) {
        // Web: Use FilePicker to pick the image
        _webImage = await getFileFromFilePicker();
        if (_webImage != null) {
          setState(() {
            _image = null; // Reset _image for web
            _errorMessage = null; // Clear any previous error message
          });
        }
      } else {
        // Mobile: Use ImagePicker to pick the image
        final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (pickedFile != null) {
          setState(() {
            _image = pickedFile;
            _webImage = null; // Reset _webImage for mobile
            _errorMessage = null; // Clear any previous error message
          });
        }
      }
    } catch (e) {
      print('Error picking image: $e'); // Log error to console
      setState(() {
        _errorMessage = "Failed to pick image: $e";
      });
    }
  }

  // Function to upload image to Firebase Storage
  Future<void> _uploadImage() async {
    try {
      // Check if an image is selected
      if (_image == null && _webImage == null) {
        setState(() {
          _errorMessage = "No image selected.";
        });
        return;
      }

      // Get the current user's email
      String? userEmail = FirebaseAuth.instance.currentUser?.email;
      if (userEmail == null) {
        setState(() {
          _errorMessage = "User not logged in.";
        });
        return;
      }

      // Create a reference to the Firebase Storage location
      final fileName = DateTime.now().toIso8601String() + (_image != null ? '.png' : '.jpg');
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('uploads/$userEmail/$fileName');

      // Upload the file
      if (kIsWeb) {
        // Web: Use putData to upload file bytes
        await storageRef.putData(_webImage!, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        // Mobile: Use putFile to upload file
        await storageRef.putFile(File(_image!.path), SettableMetadata(contentType: 'image/png'));
      }

      // Get the download URL
      String downloadUrl = await storageRef.getDownloadURL();

      setState(() {
        _imageUrl = downloadUrl;
        _errorMessage = null;
      });

      print('Image uploaded successfully: $downloadUrl'); // Log success to console

      // Show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image uploaded successfully!')),
      );

      // Close the bottom sheet
      Navigator.pop(context);
    } catch (e) {
      print('Error uploading image: $e'); // Log error to console
      setState(() {
        _errorMessage = "Failed to upload image: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Display the selected image or a placeholder text
          _imageUrl != null
              ? Image.network(
            _imageUrl!,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading image from URL: $error'); // Log error to console
              return Container(
                width: 100,
                height: 100,
                color: Colors.red,
                child: Center(
                  child: Icon(Icons.error, color: Colors.white),
                ),
              );
            },
            loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                      : null,
                ),
              );
            },
          )
              : _image != null
              ? Image.file(File(_image!.path))
              : _webImage != null
              ? Image.memory(_webImage!)
              : Text('No image selected.'),
          if (_errorMessage != null) ...[
            SizedBox(height: 20),
            Text(_errorMessage!, style: TextStyle(color: Colors.red)),
          ],
          SizedBox(height: 20),
          // Button to pick image
          ElevatedButton(
            onPressed: _pickImage,
            child: Text('Pick Image'),
          ),
          // Button to upload image
          ElevatedButton(
            onPressed: _uploadImage,
            child: Text('Upload Image'),
          ),
        ],
      ),
    );
  }
}