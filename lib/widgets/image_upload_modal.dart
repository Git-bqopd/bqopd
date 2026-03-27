import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

class ImageUploadModal extends StatefulWidget {
  final String userId;

  const ImageUploadModal({super.key, required this.userId});

  @override
  State<ImageUploadModal> createState() => _ImageUploadModalState();
}

class _ImageUploadModalState extends State<ImageUploadModal> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  File? _imageFile;
  Uint8List? _webImageBytes;
  String? _pickedFileName;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();

  // --- Archival Metadata State ---
  final TextEditingController _indiciaController = TextEditingController();
  final List<Map<String, dynamic>> _creators = [];
  final TextEditingController _newCreatorNameController = TextEditingController();
  final TextEditingController _newCreatorRoleController = TextEditingController();

  bool _isUploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _setupDefaultMetadata();
  }

  Future<void> _setupDefaultMetadata() async {
    try {
      final doc = await _firestore.collection('Users').doc(widget.userId).get();
      if (doc.exists) {
        final data = doc.data();
        final name = data?['displayName'] ?? data?['username'] ?? 'Anonymous Creator';

        setState(() {
          _creators.add({
            'uid': widget.userId,
            'name': name,
            'role': 'Creator',
          });

          final currentYear = DateTime.now().year;
          _indiciaController.text = "© $currentYear $name. All rights reserved.";
        });
      }
    } catch (e) {
      debugPrint("Error fetching user defaults: $e");
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        _pickedFileName = pickedFile.name;
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() => _webImageBytes = bytes);
        } else {
          setState(() => _imageFile = File(pickedFile.path));
        }
      }
    } catch (e) {
      setState(() => _errorMessage = "Error picking image: $e");
    }
  }

  Future<void> _uploadPost() async {
    if (_imageFile == null && _webImageBytes == null) {
      setState(() => _errorMessage = "Please select an image first.");
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _errorMessage = "You must be logged in to upload.");
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final String fileName = _pickedFileName ?? 'image.jpg';
      final String extension = p.extension(fileName).replaceAll('.', '').isEmpty ? 'jpg' : p.extension(fileName).replaceAll('.', '');
      final String filePath = 'uploads/${widget.userId}/$fileName';

      final Reference storageRef = _storage.ref().child(filePath);

      TaskSnapshot snapshot;
      if (kIsWeb) {
        snapshot = await storageRef.putData(_webImageBytes!, SettableMetadata(contentType: 'image/$extension'));
      } else {
        snapshot = await storageRef.putFile(_imageFile!);
      }

      final String downloadUrl = await snapshot.ref.getDownloadURL();
      final newImageRef = _firestore.collection('images').doc();

      await newImageRef.set({
        'uid': widget.userId,
        'uploaderId': user.uid,
        'fileUrl': downloadUrl,
        'fileName': fileName,
        'internalRef': newImageRef.id,
        'title': _titleController.text.trim(),
        'description': _captionController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'tags': {},
        'indicia': _indiciaController.text.trim(),
        'creators': _creators,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image uploaded successfully!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _errorMessage = "Upload failed: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _addCreator() async {
    final input = _newCreatorNameController.text.trim();
    final role = _newCreatorRoleController.text.trim();
    if (input.isEmpty || role.isEmpty) return;

    setState(() => _isUploading = true);

    String? uid;
    String name = input;

    if (input.startsWith('@')) {
      final handle = input.substring(1).toLowerCase();
      try {
        final query = await _firestore.collection('Users').where('username', isEqualTo: handle).limit(1).get();
        if (query.docs.isNotEmpty) {
          uid = query.docs.first.id;
          final data = query.docs.first.data();
          name = data['displayName'] ?? data['username'] ?? input;
        }
      } catch (e) {
        debugPrint("Error looking up user: $e");
      }
    }

    setState(() {
      _creators.add({
        'uid': uid,
        'name': name,
        'role': role,
      });
      _newCreatorNameController.clear();
      _newCreatorRoleController.clear();
      _isUploading = false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _captionController.dispose();
    _indiciaController.dispose();
    _newCreatorNameController.dispose();
    _newCreatorRoleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasImage = _imageFile != null || _webImageBytes != null;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Upload Work", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 16),

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    color: Colors.red.shade50,
                    child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade900)),
                  ),

                GestureDetector(
                  onTap: _isUploading ? null : _pickImage,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300, width: 2, style: BorderStyle.solid),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasImage
                        ? (kIsWeb
                        ? Image.memory(_webImageBytes!, fit: BoxFit.contain)
                        : Image.file(_imageFile!, fit: BoxFit.contain))
                        : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text("Tap to select image", style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: "Title", border: OutlineInputBorder(), prefixIcon: Icon(Icons.title)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _captionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: "Caption / Description", border: OutlineInputBorder(), prefixIcon: Icon(Icons.description)),
                ),
                const SizedBox(height: 16),

                _buildArchivalSection(),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isUploading ? null : _uploadPost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1B255),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isUploading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("PUBLISH TO GALLERY", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArchivalSection() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: ExpansionTile(
        title: const Text("Archival Metadata & Credits", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: const Text("Indicia, copyright, and co-creators", style: TextStyle(fontSize: 12, color: Colors.grey)),
        childrenPadding: const EdgeInsets.all(16.0),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Indicia / Copyright Notice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _indiciaController,
            maxLines: 3,
            style: const TextStyle(fontSize: 12, fontFamily: 'Georgia'),
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: "Enter copyright boilerplate..."),
          ),
          const SizedBox(height: 20),

          const Text("Creators", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),

          if (_creators.isEmpty)
            const Text("No creators added.", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Colors.grey)),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _creators.length,
            itemBuilder: (context, index) {
              final creator = _creators[index];
              final String role = (creator['role'] ?? 'Creator').toString().toUpperCase();
              final String fallbackName = (creator['name'] ?? 'Unknown').toString().toUpperCase();
              final String? uid = creator['uid'];
              final bool isSelf = uid == widget.userId;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 55,
                        child: Text(role, style: const TextStyle(fontSize: 9, color: Colors.black54, fontWeight: FontWeight.bold), textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis)
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(fontSize: 12, color: Colors.black12))),
                    Expanded(child: _buildCreatorInfo(uid, fallbackName)),
                    if (!isSelf)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: InkWell(onTap: () => setState(() => _creators.removeAt(index)), child: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 20)),
                      )
                  ],
                ),
              );
            },
          ),

          const Divider(height: 24),
          const Text("Add Co-Creator", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _newCreatorNameController,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(hintText: "Search user by @handle...", prefixIcon: Icon(Icons.search, size: 18), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12), border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _newCreatorRoleController,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(hintText: "Role (e.g. Inker)", isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12), border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isUploading ? null : _addCreator,
                icon: const Icon(Icons.add_circle, color: Color(0xFFF1B255), size: 32),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorInfo(String? uid, String fallbackName) {
    if (uid == null || uid.isEmpty) {
      return Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), shape: BoxShape.circle, border: Border.all(color: Colors.black.withOpacity(0.1))),
              child: Center(child: Text(fallbackName.isNotEmpty ? fallbackName[0] : '?', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fallbackName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text("Guest Contributor", style: TextStyle(fontSize: 8, color: Colors.black.withOpacity(0.4), fontStyle: FontStyle.italic)),
                ],
              ),
            )
          ]
      );
    }

    return FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('Users').doc(uid).get(),
        builder: (context, snap) {
          String name = fallbackName;
          String handle = "fetching...";
          String? photoUrl;

          if (snap.hasData && snap.data!.exists) {
            final data = snap.data!.data() as Map<String, dynamic>;
            name = (data['displayName'] ?? data['username'] ?? fallbackName).toString().toUpperCase();
            handle = "@${data['username'] ?? 'user'}".toLowerCase();
            photoUrl = data['photoUrl'];
          } else if (snap.connectionState == ConnectionState.done) {
            handle = "@unknown";
          }

          return Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), shape: BoxShape.circle, border: Border.all(color: Colors.black.withOpacity(0.1))),
                  clipBehavior: Clip.antiAlias,
                  child: photoUrl != null
                      ? ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ]),
                      child: Image.network(photoUrl, fit: BoxFit.cover))
                      : Center(child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(handle, style: TextStyle(fontSize: 8, color: Colors.black.withOpacity(0.4))),
                    ],
                  ),
                ),
              ]
          );
        }
    );
  }
}