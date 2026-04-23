import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'base_fanzine_workspace.dart';
import 'reader_panels/credits_panel.dart';
import 'folio_image_selector_modal.dart';
import '../blocs/fanzine_editor_bloc.dart';
import '../services/user_provider.dart';

class FanzineMakerWidget extends StatelessWidget {
  final String fanzineId;
  const FanzineMakerWidget({super.key, required this.fanzineId});

  @override
  Widget build(BuildContext context) {
    return BaseFanzineWorkspace(
      fanzineId: fanzineId,
      customTabs: const [
        Tab(text: "upload", icon: Icon(Icons.upload, size: 20)),
      ],
      customTabViews: [
            (context, fanzine, pages) => _MakerUploadTab(fanzineId: fanzineId, folioTitle: fanzine.title),
      ],
      onSaveCallback: () {
        if (context.canPop()) {
          context.pop();
        } else {
          final userProvider = Provider.of<UserProvider>(context, listen: false);
          final username = userProvider.userProfile?.username;
          if (username != null) {
            context.go('/$username', extra: {'tab': 'maker', 'drafts': true});
          } else {
            context.go('/');
          }
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
    final snap = await FirebaseFirestore.instance.collection('fanzines').where('ownerId', isEqualTo: user.uid).get();
    if (mounted) setState(() => _folioNames = {for (var doc in snap.docs) doc.id: doc.data()['title'] ?? 'untitled'});
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
        context.read<FanzineEditorBloc>().add(AddExistingImageRequested(imageDocRef.id, url, width: decodedImage.width, height: decodedImage.height));
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(is5x8 ? 'full page added successfully!' : 'asset uploaded successfully!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('upload error: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _openOrphanSelector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final result = await showDialog<List<Map<String, dynamic>>>(context: context, builder: (context) => FolioImageSelectorModal(userId: user.uid));
    if (result != null && result.isNotEmpty && mounted) {
      final bloc = context.read<FanzineEditorBloc>();
      for (final img in result) {
        int? w = img['width']; int? h = img['height'];
        if (w == null || h == null) {
          try {
            final response = await http.get(Uri.parse(img['fileUrl']));
            final decoded = await decodeImageFromList(response.bodyBytes);
            w = decoded.width; h = decoded.height;
            FirebaseFirestore.instance.collection('images').doc(img['id']).update({'width': w, 'height': h, 'aspectRatio': w / h});
          } catch (_) {}
        }
        bloc.add(AddExistingImageRequested(img['id'], img['fileUrl'], width: w, height: h));
      }
    }
  }

  String _getBadgeLabel(Map<String, dynamic> data) {
    final List usedIn = data['usedInFanzines'] ?? [];
    final String? context = data['folioContext'];
    if (context != null && context != widget.fanzineId) return _folioNames[context] ?? "other folio";
    if (context == null && usedIn.contains(widget.fanzineId)) return "orphan";
    if (context == widget.fanzineId) return widget.folioTitle;
    return "orphan";
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
        title: Text(isDirect ? "delete image completely?" : "remove from folio?"),
        content: Text(isDirect ? "this is a direct upload. deleting it will remove it from ALL folios and your library." : "this image exists in your library. removing it here will not delete the source file."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("cancel", style: TextStyle(color: Colors.black))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isDirect ? "delete" : "remove", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirm == true && mounted) context.read<FanzineEditorBloc>().add(DeleteAssetRequested(imageId, isDirect));
  }

  Widget _buildGrid(List<QueryDocumentSnapshot> documents) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.625, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final data = doc.data() as Map<String, dynamic>;
        final url = data['gridUrl'] ?? data['fileUrl'];
        final title = data['title'] ?? data['fileName'] ?? 'untitled';
        final badge = _getBadgeLabel(data);
        final width = data['width'];
        final height = data['height'];
        final isDirect = data['folioContext'] == widget.fanzineId;

        return GestureDetector(
          onTap: () => showDialog(context: context, builder: (c) => _AssetEditModal(imageId: doc.id, data: data)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12), image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null)),
              Positioned(
                top: 26, left: 4, right: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey.shade800.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
                      child: Text(badge.toLowerCase(), style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                top: 2, right: 2,
                child: GestureDetector(
                  onTap: () => _handleDelete(doc.id, isDirect),
                  child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle), child: Icon(isDirect ? Icons.delete_outline : Icons.close, size: 14, color: Colors.white)),
                ),
              ),
              Align(alignment: Alignment.bottomCenter, child: Container(width: double.infinity, decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))), padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4), child: Text(title.toLowerCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis))),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("please sign in."));
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: ElevatedButton(
                      onPressed: _isUploading ? null : _uploadImage,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey, // Grayscale
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12)
                      ),
                      child: _isUploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("upload new image", style: TextStyle(fontSize: 12))
                  )
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: ElevatedButton(
                      onPressed: _openOrphanSelector,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey, // Grayscale
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12)
                      ),
                      child: const Text("select orphan image", style: TextStyle(fontSize: 12))
                  )
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('images').where('uploaderId', isEqualTo: user.uid).orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator(color: Colors.black)));
              final folioDocs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['folioContext'] == widget.fanzineId || (data['usedInFanzines'] ?? []).contains(widget.fanzineId);
              }).toList();
              if (folioDocs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 48.0), child: Text("no images in this folio yet.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)));
              final fiveByEightDocs = folioDocs.where((d) => _isImage5x8(d.data() as Map<String, dynamic>)).toList();
              final otherDocs = folioDocs.where((d) => !_isImage5x8(d.data() as Map<String, dynamic>)).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fiveByEightDocs.isNotEmpty) ...[const SizedBox(height: 16), const Text("full pages (5x8)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 8), _buildGrid(fiveByEightDocs), const SizedBox(height: 24)],
                  if (otherDocs.isNotEmpty) ...[const SizedBox(height: 16), const Text("inline assets", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 8), _buildGrid(otherDocs), const SizedBox(height: 24)],
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
  void initState() { super.initState(); _titleController = TextEditingController(text: widget.data['title'] ?? widget.data['fileName'] ?? ''); }
  @override
  void dispose() { _titleController.dispose(); super.dispose(); }
  Future<void> _saveTitle() async {
    setState(() => _isSavingTitle = true);
    try { await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({'title': _titleController.text.trim()}); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('title saved!'))); } finally { if (mounted) setState(() => _isSavingTitle = false); }
  }
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: LayoutBuilder(builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          final url = widget.data['fileUrl'] ?? '';
          final imgWidget = Container(color: Colors.grey[200], width: isMobile ? double.infinity : null, height: isMobile ? 200 : null, child: ClipRRect(borderRadius: isMobile ? const BorderRadius.vertical(top: Radius.circular(12)) : const BorderRadius.horizontal(left: Radius.circular(12)), child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))));
          final editWidget = Padding(padding: const EdgeInsets.all(24.0), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("asset details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))]), const Divider(), Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text("asset name / title", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: _titleController, decoration: const InputDecoration(border: OutlineInputBorder(), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)), isDense: true))), const SizedBox(width: 8), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white), onPressed: _isSavingTitle ? null : _saveTitle, child: Text(_isSavingTitle ? "saving..." : "save name"))]), const SizedBox(height: 12), TextField(readOnly: true, controller: TextEditingController(text: url), decoration: const InputDecoration(labelText: "url", border: OutlineInputBorder(), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)), floatingLabelStyle: TextStyle(color: Colors.black87), isDense: true, filled: true, fillColor: Color(0xFFF5F5F5)), style: const TextStyle(fontFamily: 'Courier', fontSize: 11)), const SizedBox(height: 24), const Divider(), const SizedBox(height: 16), CreditsPanel(imageId: widget.imageId)])))]));
          return isMobile ? Column(children: [imgWidget, Expanded(child: editWidget)]) : Row(children: [Expanded(child: imgWidget), Expanded(child: editWidget)]);
        }),
      ),
    );
  }
}