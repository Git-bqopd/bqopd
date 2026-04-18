import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'base_fanzine_workspace.dart';
import 'reader_panels/credits_panel.dart';

class FanzineMakerWidget extends StatelessWidget {
  final String fanzineId;
  const FanzineMakerWidget({super.key, required this.fanzineId});

  @override
  Widget build(BuildContext context) {
    return BaseFanzineWorkspace(
      fanzineId: fanzineId,
      customTabs: const [
        Tab(text: "Upload", icon: Icon(Icons.upload, size: 20)),
      ],
      customTabViews: [
            (context, fanzine, pages) => _MakerUploadTab(fanzineId: fanzineId),
      ],
      onSaveCallback: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/profile?tab=maker&drafts=true');
        }
      },
    );
  }
}

class _MakerUploadTab extends StatefulWidget {
  final String fanzineId;

  const _MakerUploadTab({required this.fanzineId});

  @override
  State<_MakerUploadTab> createState() => _MakerUploadTabState();
}

class _MakerUploadTabState extends State<_MakerUploadTab> {
  bool _isUploading = false;

  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = await file.readAsBytes();

      final decodedImage = await decodeImageFromList(bytes);
      final double ratio = decodedImage.width / decodedImage.height;
      final bool is5x8 = (ratio >= 0.60 && ratio <= 0.65);

      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'unknown';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      final path = 'uploads/$uid/folio_assets/${widget.fanzineId}/$fileName';

      final ref = FirebaseStorage.instance.ref().child(path);
      final uploadTask = await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await uploadTask.ref.getDownloadURL();

      final imageDocRef = await FirebaseFirestore.instance.collection('images').add({
        'uploaderId': uid,
        'folioContext': widget.fanzineId,
        'fileUrl': url,
        'fileName': file.name,
        'title': file.name,
        'status': 'approved',
        'timestamp': FieldValue.serverTimestamp(),
        'isFolioAsset': true,
        'width': decodedImage.width,
        'height': decodedImage.height,
        'aspectRatio': ratio,
        'is5x8': is5x8,
      });

      if (is5x8) {
        final pagesSnap = await FirebaseFirestore.instance
            .collection('fanzines')
            .doc(widget.fanzineId)
            .collection('pages')
            .orderBy('pageNumber', descending: true)
            .limit(1)
            .get();

        int nextNum = 1;
        if (pagesSnap.docs.isNotEmpty) {
          nextNum = (pagesSnap.docs.first.data()['pageNumber'] ?? 0) + 1;
        }

        await FirebaseFirestore.instance
            .collection('fanzines')
            .doc(widget.fanzineId)
            .collection('pages')
            .add({
          'imageId': imageDocRef.id,
          'imageUrl': url,
          'pageNumber': nextNum,
          'status': 'ready',
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(is5x8 ? 'Full page added successfully!' : 'Asset uploaded successfully!'))
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload Error: $e'))
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _buildGrid(List<QueryDocumentSnapshot> documents) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final data = documents[index].data() as Map<String, dynamic>;
        final url = data['fileUrl'];
        final title = data['title'] ?? data['fileName'] ?? 'Untitled';
        final is5x8 = data['is5x8'] == true;

        return GestureDetector(
          onTap: () {
            showDialog(
                context: context,
                builder: (c) => _AssetEditModal(imageId: documents[index].id, data: data)
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                  image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
                ),
              ),
              if (is5x8)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "5:8",
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("FOLIO ASSETS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text("Upload images to be used in the text editor or as standalone 5x8 page components. They will be stored in your library.", style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadImage,
            icon: _isUploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_photo_alternate),
            label: Text(_isUploading ? "Uploading..." : "Upload New Image"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('images')
                .where('folioContext', isEqualTo: widget.fanzineId)
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final errorMsg = snapshot.error.toString();
                return Center(child: SelectableText("Error: $errorMsg"));
              }

              if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator()));

              final docs = snapshot.data!.docs;

              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text("No images uploaded to this folio yet.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                );
              }

              final fiveByEightDocs = docs.where((d) => (d.data() as Map<String, dynamic>)['is5x8'] == true).toList();
              final otherDocs = docs.where((d) => (d.data() as Map<String, dynamic>)['is5x8'] != true).toList();

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fiveByEightDocs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text("FULL PAGES (5x8)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      _buildGrid(fiveByEightDocs),
                      const SizedBox(height: 24),
                    ],
                    if (otherDocs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text("INLINE ASSETS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      _buildGrid(otherDocs),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AssetEditModal extends StatefulWidget {
  final String imageId;
  final Map<String, dynamic> data;

  // FIXED: Removed unused super.key from private constructor to resolve warning
  const _AssetEditModal({required this.imageId, required this.data});

  @override
  State<_AssetEditModal> createState() => _AssetEditModalState();
}

class _AssetEditModalState extends State<_AssetEditModal> {
  late TextEditingController _titleController;
  bool _isSavingTitle = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.data['title'] ?? widget.data['fileName'] ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveTitle() async {
    setState(() => _isSavingTitle = true);
    try {
      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({
        'title': _titleController.text.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title saved!')));
    } finally {
      if (mounted) setState(() => _isSavingTitle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final url = widget.data['fileUrl'] ?? '';

              final imgWidget = Container(
                color: Colors.grey[200],
                width: isMobile ? double.infinity : null,
                height: isMobile ? 200 : null,
                child: ClipRRect(
                  borderRadius: isMobile
                      ? const BorderRadius.vertical(top: Radius.circular(12))
                      : const BorderRadius.horizontal(left: Radius.circular(12)),
                  child: InteractiveViewer(
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              );

              final editWidget = Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("ASSET DETAILS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text("Asset Name / Title", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _titleController,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _isSavingTitle ? null : _saveTitle,
                                  child: Text(_isSavingTitle ? "Saving..." : "Save Name"),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              readOnly: true,
                              controller: TextEditingController(text: url),
                              decoration: const InputDecoration(
                                  labelText: "URL (For text {{IMAGE: ...}} tags)",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Color(0xFFF5F5F5)
                              ),
                              style: const TextStyle(fontFamily: 'Courier', fontSize: 11),
                            ),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),
                            CreditsPanel(imageId: widget.imageId),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    imgWidget,
                    Expanded(child: editWidget),
                  ],
                );
              } else {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 1, child: imgWidget),
                    Expanded(flex: 1, child: editWidget),
                  ],
                );
              }
            }
        ),
      ),
    );
  }
}