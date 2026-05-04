import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import '../../blocs/fanzine_editor_bloc.dart';
import '../../blocs/upload/upload_bloc.dart';
import '../folio_image_selector_modal.dart';
import '../reader_panels/credits_panel.dart';

class CuratorUploadTab extends StatefulWidget {
  final String fanzineId;
  final String folioTitle;

  const CuratorUploadTab({super.key, required this.fanzineId, required this.folioTitle});

  @override
  State<CuratorUploadTab> createState() => _CuratorUploadTabState();
}

class _CuratorUploadTabState extends State<CuratorUploadTab> {
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
    if (mounted) {
      setState(() => _folioNames = {for (var doc in snap.docs) doc.id: doc.data()['title'] ?? 'untitled'});
    }
  }

  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final bytes = await file.readAsBytes();

    if (mounted) {
      context.read<UploadBloc>().add(UploadFolioAssetRequested(
        bytes: bytes,
        fileName: file.name,
        fanzineId: widget.fanzineId,
        userId: user.uid,
      ));
    }
  }

  Future<void> _openOrphanSelector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final result = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (context) => FolioImageSelectorModal(userId: user.uid)
    );

    if (!mounted) return;

    if (result != null && result.isNotEmpty) {
      final bloc = context.read<FanzineEditorBloc>();
      for (final img in result) {
        int? w = img['width'];
        int? h = img['height'];
        if (w == null || h == null) {
          // Attempt recovery if dimensions are missing
          try {
            final response = await http.get(Uri.parse(img['fileUrl']));
            final decoded = await decodeImageFromList(response.bodyBytes);
            w = decoded.width;
            h = decoded.height;
            FirebaseFirestore.instance.collection('images').doc(img['id']).update({'width': w, 'height': h, 'aspectRatio': w / h});
          } catch (_) {}
        }
        bloc.add(AddExistingImageRequested(img['id'], img['fileUrl'], width: w, height: h));
      }
    }
  }

  String _getBadgeLabel(Map<String, dynamic> data) {
    final List usedIn = data['usedInFanzines'] ?? [];
    final String? contextId = data['folioContext'];
    if (contextId != null && contextId != widget.fanzineId) return _folioNames[contextId] ?? "other folio";
    if (contextId == null && usedIn.contains(widget.fanzineId)) return "orphan";
    if (contextId == widget.fanzineId) return widget.folioTitle;
    return "orphan";
  }

  Future<void> _handleDelete(String imageId, bool isDirect) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDirect ? "Delete Image Completely?" : "Remove from Folio?"),
        content: Text(isDirect
            ? "This is a direct upload. Deleting it will remove it from ALL issues and your master library forever."
            : "This image exists in your library. Removing it here will only delete it from this specific folio."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("cancel", style: TextStyle(color: Colors.black))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isDirect ? "DELETE FOREVER" : "REMOVE",
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
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
          crossAxisCount: 3, childAspectRatio: 0.625, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final data = doc.data() as Map<String, dynamic>;

        final String? url = data['gridUrl'] ?? data['listUrl'] ?? data['fileUrl'];

        final title = data['title'] ?? data['fileName'] ?? 'untitled';
        final badge = _getBadgeLabel(data);
        final width = data['width'];
        final height = data['height'];
        final isDirect = data['folioContext'] == widget.fanzineId;

        return GestureDetector(
          onTap: () => showDialog(context: context, builder: (c) => _CuratorAssetEditModal(imageId: doc.id, data: data)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                  decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                      image: (url != null && url.isNotEmpty) ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null)),

              if (url == null || url.isEmpty)
                const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)),

              Positioned(
                top: 26, left: 4, right: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey.shade800.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
                      child: Text(badge.toLowerCase(), style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
                      child: Text("${width ?? '??'}x${height ?? '??'}", style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2, right: 2,
                child: GestureDetector(
                  onTap: () => _handleDelete(doc.id, isDirect),
                  child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Icon(
                        isDirect ? Icons.delete_forever : Icons.close,
                        size: 16,
                        color: isDirect ? Colors.redAccent : Colors.white,
                      )),
                ),
              ),
              Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Text(title.toLowerCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 9),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis))),
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

    return BlocConsumer<UploadBloc, UploadState>(
        listenWhen: (previous, current) => current.status != previous.status,
        listener: (context, state) {
          if (state.status == UploadStatus.folioAssetSuccess && state.uploadedImageId != null) {
            if (state.is5x8 == true) {
              context.read<FanzineEditorBloc>().add(AddExistingImageRequested(
                  state.uploadedImageId!,
                  state.uploadedImageUrl!,
                  width: state.width,
                  height: state.height
              ));
            }
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.is5x8 == true ? 'full page added successfully!' : 'asset uploaded successfully!')));
            context.read<UploadBloc>().add(ResetUploadState());
          } else if (state.status == UploadStatus.failure && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('upload error: ${state.errorMessage}')));
            context.read<UploadBloc>().add(ResetUploadState());
          }
        },
        builder: (context, state) {
          final bool isUploading = state.status == UploadStatus.folioAssetSubmitting;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: ElevatedButton(
                            onPressed: isUploading ? null : _uploadImage,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: isUploading
                                ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text("upload new image", style: TextStyle(fontSize: 12)))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: ElevatedButton(
                            onPressed: _openOrphanSelector,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: const Text("select orphan image", style: TextStyle(fontSize: 12)))),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('images').orderBy('timestamp', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                          child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator(color: Colors.black)));
                    }

                    final folioDocs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['folioContext'] == widget.fanzineId || (data['usedInFanzines'] ?? []).contains(widget.fanzineId);
                    }).toList();

                    if (folioDocs.isEmpty) {
                      return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48.0),
                          child: Text("no images in this folio yet.",
                              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)));
                    }

                    final uploadedDocs = folioDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final path = data['storagePath']?.toString() ?? '';
                      return path.startsWith('uploads/') || path.isEmpty;
                    }).toList();

                    final pdfDocs = folioDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final path = data['storagePath']?.toString() ?? '';
                      return path.startsWith('fanzines/');
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (uploadedDocs.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text("uploaded", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 8),
                          _buildGrid(uploadedDocs),
                          const SizedBox(height: 24)
                        ],
                        if (pdfDocs.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text("from PDF", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 8),
                          _buildGrid(pdfDocs),
                          const SizedBox(height: 24)
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        }
    );
  }
}

class _CuratorAssetEditModal extends StatefulWidget {
  final String imageId;
  final Map<String, dynamic> data;
  const _CuratorAssetEditModal({required this.imageId, required this.data});
  @override
  State<_CuratorAssetEditModal> createState() => _CuratorAssetEditModalState();
}

class _CuratorAssetEditModalState extends State<_CuratorAssetEditModal> {
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('title saved!')));
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
        child: LayoutBuilder(builder: (context, constraints) {
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
                  child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))));

          final editWidget = Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("asset details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
                ]),
                const Divider(),
                Expanded(
                    child: SingleChildScrollView(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Text("asset name / title", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: _titleController,
                                    decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                                        isDense: true))),
                            const SizedBox(width: 8),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                                onPressed: _isSavingTitle ? null : _saveTitle,
                                child: Text(_isSavingTitle ? "saving..." : "save name"))
                          ]),
                          const SizedBox(height: 12),
                          TextField(
                              readOnly: true,
                              controller: TextEditingController(text: url),
                              decoration: const InputDecoration(
                                  labelText: "url",
                                  border: OutlineInputBorder(),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                                  floatingLabelStyle: TextStyle(color: Colors.black87),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Color(0xFFF5F5F5)),
                              style: const TextStyle(fontFamily: 'Courier', fontSize: 11)),
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          CreditsPanel(imageId: widget.imageId)
                        ])))
              ]));

          return isMobile ? Column(children: [imgWidget, Expanded(child: editWidget)]) : Row(children: [Expanded(child: imgWidget), Expanded(child: editWidget)]);
        }),
      ),
    );
  }
}