import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'base_fanzine_workspace.dart';
import 'reader_panels/credits_panel.dart';
import 'folio_image_selector_modal.dart';
import '../blocs/fanzine_editor_bloc.dart';

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
            (context, fanzine, pages) => _MakerUploadTab(fanzineId: fanzineId, folioTitle: fanzine.title),
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
  final String folioTitle;

  const _MakerUploadTab({required this.fanzineId, required this.folioTitle});

  @override
  State<_MakerUploadTab> createState() => _MakerUploadTabState();
}

class _MakerUploadTabState extends State<_MakerUploadTab> {
  bool _isUploading = false;
  Map<String, String> _folioNames = {};

  @override
  void initState() {
    super.initState();
    _loadFolioNames();
  }

  Future<void> _loadFolioNames() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('fanzines')
        .where('ownerId', isEqualTo: user.uid)
        .get();

    if (mounted) {
      setState(() {
        _folioNames = {for (var doc in snap.docs) doc.id: doc.data()['title'] ?? 'Untitled'};
      });
    }
  }

  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = await file.readAsBytes();
      final decodedImage = await decodeImageFromList(bytes);
      final double ratio = decodedImage.width / decodedImage.height;
      final bool is5x8 = (ratio >= 0.58 && ratio <= 0.67);

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
        'usedInFanzines': [widget.fanzineId],
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
        context.read<FanzineEditorBloc>().add(AddExistingImageRequested(
          imageDocRef.id,
          url,
          width: decodedImage.width,
          height: decodedImage.height,
        ));
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

  Future<void> _openOrphanSelector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => FolioImageSelectorModal(userId: user.uid),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final bloc = context.read<FanzineEditorBloc>();
      for (final img in result) {
        int? w = img['width'];
        int? h = img['height'];

        if (w == null || h == null) {
          try {
            final response = await http.get(Uri.parse(img['fileUrl']));
            final decoded = await decodeImageFromList(response.bodyBytes);
            w = decoded.width;
            h = decoded.height;
            FirebaseFirestore.instance.collection('images').doc(img['id']).update({
              'width': w, 'height': h, 'aspectRatio': w / h,
            });
          } catch (_) {}
        }

        bloc.add(AddExistingImageRequested(
          img['id'], img['fileUrl'], width: w, height: h,
        ));
      }
    }
  }

  String _getBadgeLabel(Map<String, dynamic> data) {
    final List usedIn = data['usedInFanzines'] ?? [];
    final String? context = data['folioContext'];
    if (context != null && context != widget.fanzineId) return _folioNames[context] ?? "Other Folio";
    if (context == null && usedIn.contains(widget.fanzineId)) return "Orphan";
    if (context == widget.fanzineId) return widget.folioTitle;
    return "Orphan";
  }

  bool _isImage5x8(Map<String, dynamic> data) {
    if (data['is5x8'] == true) return true;
    final w = data['width'] as num?;
    final h = data['height'] as num?;
    if (w != null && h != null) {
      final ratio = w / h;
      return ratio >= 0.58 && ratio <= 0.67;
    }
    return false;
  }

  Future<void> _handleDelete(String imageId, bool isDirect) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDirect ? "Delete Image Completely?" : "Remove from Folio?"),
        content: Text(isDirect
            ? "This is a direct upload. Deleting it will remove it from ALL folios and your library."
            : "This image exists in your library. Removing it here will not delete the source file."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isDirect ? "DELETE" : "REMOVE", style: const TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      context.read<FanzineEditorBloc>().add(DeleteAssetRequested(imageId, isDirect));
    }
  }

  Widget _buildGrid(List<QueryDocumentSnapshot> documents) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 0.625, crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final data = doc.data() as Map<String, dynamic>;

        // OPTIMIZATION: Pull the 450px grid thumbnail if available
        final url = data['gridUrl'] ?? data['fileUrl'];

        final title = data['title'] ?? data['fileName'] ?? 'Untitled';
        final badge = _getBadgeLabel(data);
        final width = data['width'];
        final height = data['height'];
        final isDirect = data['folioContext'] == widget.fanzineId;

        return GestureDetector(
          onTap: () {
            showDialog(
                context: context,
                builder: (c) => _AssetEditModal(imageId: doc.id, data: data)
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12),
                  image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
                ),
              ),
              Positioned(
                top: 26, left: 4, right: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: badge == "Orphan" ? Colors.redAccent.withOpacity(0.8) : Colors.indigo.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badge.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
                      child: Text("${width ?? '??'}x${height ?? '??'}", style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => _handleDelete(doc.id, isDirect),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                        isDirect ? Icons.delete_outline : Icons.close,
                        size: 14,
                        color: Colors.white
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please sign in."));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _uploadImage,
                  icon: _isUploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_photo_alternate, size: 18),
                  label: Text(_isUploading ? "Uploading..." : "Upload New Image", style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openOrphanSelector,
                  icon: const Icon(Icons.manage_search, size: 18),
                  label: const Text("Select Orphan Image", style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('images').where('uploaderId', isEqualTo: user.uid).orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator()));
              final allUserDocs = snapshot.data!.docs;
              final folioDocs = allUserDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final List usedIn = data['usedInFanzines'] ?? [];
                return data['folioContext'] == widget.fanzineId || usedIn.contains(widget.fanzineId);
              }).toList();

              if (folioDocs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 48.0), child: Text("No images in this folio yet.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)));

              final fiveByEightDocs = folioDocs.where((d) => _isImage5x8(d.data() as Map<String, dynamic>)).toList();
              final otherDocs = folioDocs.where((d) => !_isImage5x8(d.data() as Map<String, dynamic>)).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fiveByEightDocs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text("FULL PAGES (5x8)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    _buildGrid(fiveByEightDocs),
                    const SizedBox(height: 24),
                  ],
                  if (otherDocs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text("INLINE ASSETS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    _buildGrid(otherDocs),
                    const SizedBox(height: 24),
                  ],
                ],
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
      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({'title': _titleController.text.trim()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title saved!')));
    } finally {
      if (mounted) setState(() => _isSavingTitle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final url = widget.data['fileUrl'] ?? '';

              final imgWidget = Container(
                color: Colors.grey[200], width: isMobile ? double.infinity : null, height: isMobile ? 200 : null,
                child: ClipRRect(
                  borderRadius: isMobile ? const BorderRadius.vertical(top: Radius.circular(12)) : const BorderRadius.horizontal(left: Radius.circular(12)),
                  child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
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
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                                Expanded(child: TextField(controller: _titleController, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true))),
                                const SizedBox(width: 8),
                                ElevatedButton(onPressed: _isSavingTitle ? null : _saveTitle, child: Text(_isSavingTitle ? "Saving..." : "Save Name")),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(readOnly: true, controller: TextEditingController(text: url), decoration: const InputDecoration(labelText: "URL", border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Color(0xFFF5F5F5)), style: const TextStyle(fontFamily: 'Courier', fontSize: 11)),
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

              return isMobile ? Column(children: [imgWidget, Expanded(child: editWidget)]) : Row(children: [Expanded(child: imgWidget), Expanded(child: editWidget)]);
            }
        ),
      ),
    );
  }
}