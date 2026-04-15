import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../blocs/fanzine_editor_bloc.dart';
import '../repositories/fanzine_repository.dart';
import 'reader_panels/credits_panel.dart'; // FIXED: Removed the extra ../

class FanzineMakerWidget extends StatelessWidget {
  final String fanzineId;
  const FanzineMakerWidget({super.key, required this.fanzineId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FanzineEditorBloc(
        repository: RepositoryProvider.of<FanzineRepository>(context),
        fanzineId: fanzineId,
      )..add(LoadFanzineRequested(fanzineId)),
      child: _FanzineMakerView(fanzineId: fanzineId),
    );
  }
}

class _FanzineMakerView extends StatefulWidget {
  final String fanzineId;
  const _FanzineMakerView({required this.fanzineId});

  @override
  State<_FanzineMakerView> createState() => _FanzineMakerViewState();
}

class _FanzineMakerViewState extends State<_FanzineMakerView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _shortcodeController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  late TabController _tabController;
  String? _lastSyncedTitle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _shortcodeController.dispose();
    _titleController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FanzineEditorBloc, FanzineEditorState>(
      listener: (context, state) {
        if (state is FanzineEditorFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      builder: (context, state) {
        if (state is FanzineEditorLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is FanzineEditorLoaded) {
          final data = state.fanzineData;
          final title = data['title'] ?? 'Untitled';
          final shortCode = data['shortCode'];
          final twoPage = data['twoPage'] ?? false;

          if (_lastSyncedTitle != title) {
            _titleController.text = title;
            _lastSyncedTitle = title;
          }

          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabBar(
                      controller: _tabController,
                      labelColor: Theme.of(context).primaryColor,
                      unselectedLabelColor: Colors.grey,
                      tabs: const [
                        Tab(text: "Settings", icon: Icon(Icons.settings, size: 20)),
                        Tab(text: "Order", icon: Icon(Icons.format_list_numbered, size: 20)),
                        Tab(text: "Upload", icon: Icon(Icons.upload, size: 20)),
                      ],
                    ),
                    _buildTabContent(context, state, shortCode, twoPage),
                  ],
                ),
              ),
              if (state.isProcessing)
                Positioned.fill(
                  child: Container(
                    color: Colors.white60,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
        }

        return const Center(child: Text("Error loading maker."));
      },
    );
  }

  Widget _buildTabContent(
      BuildContext context,
      FanzineEditorLoaded state,
      String? shortCode,
      bool twoPage,
      ) {
    switch (_tabController.index) {
      case 0:
        return _buildSettingsTab(
            context, state, shortCode, twoPage);
      case 1:
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PAGE ORDER',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              _PageList(pages: state.pages, onReorder: (doc, delta) {
                context.read<FanzineEditorBloc>().add(
                    ReorderPageRequested(doc, delta, state.pages));
              }),
            ],
          ),
        );
      case 2:
        return _MakerUploadTab(fanzineId: widget.fanzineId);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSettingsTab(
      BuildContext context,
      FanzineEditorLoaded state,
      String? shortCode,
      bool twoPage,
      ) {
    final bloc = context.read<FanzineEditorBloc>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            onSubmitted: (val) => bloc.add(UpdateFanzineTitle(val)),
            decoration: const InputDecoration(
                labelText: 'Folio Name',
                isDense: true,
                border: OutlineInputBorder(),
                helperText: "Press enter to save"),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _shortcodeController,
                    decoration: const InputDecoration(
                        hintText: 'Paste image shortcode',
                        isDense: true,
                        border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: state.isProcessing
                    ? null
                    : () {
                  bloc.add(AddPageRequested(_shortcodeController.text));
                  _shortcodeController.clear();
                },
                child: const Text('Add Page')),
          ]),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shortcode: ${shortCode ?? 'None'}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (shortCode == null)
                TextButton(
                  onPressed: () {},
                  child: const Text("GENERATE SHORTCODE",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                )
            ],
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Has two page spread view', style: TextStyle(fontSize: 12)),
            Switch(
                value: twoPage,
                onChanged: (val) => bloc.add(UpdateFanzineTitle(_titleController.text))),
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: state.isProcessing
                ? null
                : () {
              bloc.add(UpdateFanzineTitle(_titleController.text));
              if (context.canPop()) {
                context.pop(); // Returns to Profile if we were pushed here
              } else {
                context.go('/profile?tab=maker&drafts=true');
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white),
            child: const Text("save folio", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _PageList extends StatelessWidget {
  final List<DocumentSnapshot> pages;
  final Function(DocumentSnapshot, int) onReorder;

  const _PageList({required this.pages, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const Text('No pages added.',
          style: TextStyle(color: Colors.grey, fontSize: 12));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final doc = pages[index];
        final data = doc.data() as Map<String, dynamic>;
        final num = data['pageNumber'] ?? 0;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
          child: Row(
            children: [
              Text('$num.',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text("Page Image",
                      style: TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis)),
              IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 14),
                  onPressed: num > 1 ? () => onReorder(doc, -1) : null),
              IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 14),
                  onPressed: num < pages.length ? () => onReorder(doc, 1) : null),
            ],
          ),
        );
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

      // Calculate Aspect Ratio to group the asset
      final decodedImage = await decodeImageFromList(bytes);
      final double ratio = decodedImage.width / decodedImage.height;
      // 5:8 aspect ratio = 0.625. Allow variance for slight crop errors (0.60 to 0.65)
      final bool is5x8 = (ratio >= 0.60 && ratio <= 0.65);

      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'unknown';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      // Store in dedicated path for this folio
      final path = 'uploads/$uid/folio_assets/${widget.fanzineId}/$fileName';

      final ref = FirebaseStorage.instance.ref().child(path);
      final uploadTask = await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await uploadTask.ref.getDownloadURL();

      // Save metadata to 'images' collection
      final imageDocRef = await FirebaseFirestore.instance.collection('images').add({
        'uploaderId': uid,
        'folioContext': widget.fanzineId,
        'fileUrl': url,
        'fileName': file.name,
        'title': file.name, // Default title to filename
        'status': 'approved', // Auto-approved for maker tools
        'timestamp': FieldValue.serverTimestamp(),
        'isFolioAsset': true,
        'width': decodedImage.width,
        'height': decodedImage.height,
        'aspectRatio': ratio,
        'is5x8': is5x8,
      });

      // Automatically add full pages to the Order tab / pages subcollection
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
                if (errorMsg.contains('failed-precondition') || errorMsg.contains('requires an index')) {
                  final urlRegex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
                  final match = urlRegex.firstMatch(errorMsg);
                  final indexUrl = match?.group(0);

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("Database Index Required", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text("To view uploaded assets, a Firestore index is needed.", textAlign: TextAlign.center),
                          if (indexUrl != null) ...[
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => launchUrl(Uri.parse(indexUrl)),
                              child: const Text("Create Index"),
                            )
                          ] else
                            SelectableText(errorMsg, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                }
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

// --- ASSET EDIT MODAL (Reuses CreditsPanel) ---
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
                            // Easy copy-paste reference URL for the Publisher text area
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
                            // Reusing the EXACT Credits Panel logic from the reader!
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