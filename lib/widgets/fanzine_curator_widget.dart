import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../models/fanzine.dart';
import '../models/fanzine_page.dart';
import '../services/username_service.dart';
import '../services/user_bootstrap.dart';
import '../services/user_provider.dart';
import '../blocs/fanzine_editor_bloc.dart';
import '../repositories/fanzine_repository.dart';
import '../repositories/pipeline_repository.dart';
import 'folio_image_selector_modal.dart';
import 'reader_panels/credits_panel.dart';

class FanzineCuratorWidget extends StatefulWidget {
  final String fanzineId;
  const FanzineCuratorWidget({super.key, required this.fanzineId});

  @override
  State<FanzineCuratorWidget> createState() => _FanzineCuratorWidgetState();
}

class _FanzineCuratorWidgetState extends State<FanzineCuratorWidget> with SingleTickerProviderStateMixin {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _volumeController = TextEditingController();
  final TextEditingController _issueController = TextEditingController();
  final TextEditingController _wholeNumberController = TextEditingController();
  String? _lastSyncedTitle;

  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Curator has 4 tabs
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _volumeController.dispose();
    _issueController.dispose();
    _wholeNumberController.dispose();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _saveMeta(BuildContext tabContext) {
    tabContext.read<FanzineEditorBloc>().add(UpdateFanzineMetadata(
      _titleController.text,
      _volumeController.text,
      _issueController.text,
      _wholeNumberController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    return BlocProvider(
      create: (context) => FanzineEditorBloc(
        repository: RepositoryProvider.of<FanzineRepository>(context),
        pipelineRepository: RepositoryProvider.of<PipelineRepository>(context),
        fanzineId: widget.fanzineId,
      )..add(LoadFanzineRequested(widget.fanzineId)),
      child: Builder(
          builder: (context) {
            return BlocConsumer<FanzineEditorBloc, FanzineEditorState>(
              listener: (context, state) {
                if (state is FanzineEditorFailure) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(state.message), backgroundColor: Colors.black87),
                  );
                }
              },
              builder: (context, state) {
                if (state is FanzineEditorLoading || state is FanzineEditorInitial) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is FanzineEditorLoaded) {
                  final fanzine = state.fanzine;
                  final pages = state.pages;

                  if (!userProvider.canEditFanzine(fanzine)) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text("you do not have permission to edit this work."),
                      ),
                    );
                  }

                  return LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isGridView = constraints.maxHeight != double.infinity;

                        Widget mainContent = Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                physics: isGridView ? const NeverScrollableScrollPhysics() : null,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TabBar(
                                      controller: _tabController,
                                      labelColor: Colors.black,
                                      unselectedLabelColor: Colors.grey,
                                      indicatorColor: Colors.black,
                                      tabs: const [
                                        Tab(text: "settings", icon: Icon(Icons.settings, size: 20)),
                                        Tab(text: "order", icon: Icon(Icons.format_list_numbered, size: 20)),
                                        Tab(text: "upload", icon: Icon(Icons.upload, size: 20)),
                                        Tab(text: "OCR / Ent", icon: Icon(Icons.auto_awesome, size: 20)),
                                      ],
                                    ),
                                    _buildActiveTab(context, fanzine, pages),
                                  ],
                                ),
                              ),
                            ),
                            if (state.isProcessing)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.white60,
                                  child: const Center(child: CircularProgressIndicator(color: Colors.black)),
                                ),
                              ),
                          ],
                        );

                        if (isGridView) {
                          return mainContent;
                        } else {
                          return Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFF1B255),
                              borderRadius: BorderRadius.zero,
                            ),
                            padding: const EdgeInsets.all(10.0),
                            child: mainContent,
                          );
                        }
                      }
                  );
                }

                return const Center(child: Text("error loading workspace."));
              },
            );
          }
      ),
    );
  }

  Widget _buildActiveTab(BuildContext context, Fanzine fanzine, List<FanzinePage> pages) {
    switch (_tabController.index) {
      case 0: return _buildCuratorSettingsTab(context, fanzine);
      case 1: return _buildCuratorOrderTab(context, pages);
      case 2: return _CuratorUploadTab(fanzineId: widget.fanzineId, folioTitle: fanzine.title);
      case 3: return _buildOCREntitiesTab(context, fanzine, pages);
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildCuratorSettingsTab(BuildContext context, Fanzine fanzine) {
    if (_lastSyncedTitle != fanzine.title) {
      _titleController.text = fanzine.title;
      _volumeController.text = fanzine.volume ?? '';
      _issueController.text = fanzine.issue ?? '';
      _wholeNumberController.text = fanzine.wholeNumber ?? '';
      _lastSyncedTitle = fanzine.title;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            onSubmitted: (val) => _saveMeta(context),
            decoration: const InputDecoration(
                labelText: 'fanzine name',
                isDense: true,
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                floatingLabelStyle: TextStyle(color: Colors.black87)),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _volumeController,
                  onSubmitted: (_) => _saveMeta(context),
                  decoration: const InputDecoration(labelText: 'Volume', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _issueController,
                  onSubmitted: (_) => _saveMeta(context),
                  decoration: const InputDecoration(labelText: 'Issue', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _wholeNumberController,
                  onSubmitted: (_) => _saveMeta(context),
                  decoration: const InputDecoration(labelText: 'Whole Number', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text("SHORTCODE",
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          SelectableText(
            fanzine.shortCode ?? 'pending...',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo, letterSpacing: 1.1),
          ),
          const SizedBox(height: 20),
          const Text("COLLABORATORS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Owner: ${fanzine.ownerId == context.read<UserProvider>().currentUserId ? 'You' : fanzine.ownerId}", style: const TextStyle(fontSize: 12)),
                if (fanzine.editors.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text("Editors: ${fanzine.editors.length}", style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Enable two page spread view', style: TextStyle(fontSize: 12)),
            Switch(
                value: fanzine.twoPage,
                activeColor: Colors.grey,
                onChanged: (val) => context.read<FanzineEditorBloc>().add(ToggleTwoPageRequested(val))),
          ]),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Live on site (available via shortcode)', style: TextStyle(fontSize: 12)),
            Switch(
                value: fanzine.isLive,
                activeColor: Colors.green,
                onChanged: (val) => context.read<FanzineEditorBloc>().add(ToggleIsLiveRequested(val))),
          ]),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              _saveMeta(context);
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white),
            child: const Text("save curator session", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCuratorOrderTab(BuildContext context, List<FanzinePage> pages) {
    final bloc = context.read<FanzineEditorBloc>();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PAGE ORDER (CURATOR)',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          if (pages.isEmpty)
            const Text('No pages added.',
                style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pages.length,
              itemBuilder: (context, index) {
                final page = pages[index];
                final num = page.pageNumber;

                final String? thumbUrl = page.gridUrl ?? page.listUrl ?? page.imageUrl;
                final bool isPending = thumbUrl == null || thumbUrl.isEmpty;

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text('$num.',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          border: Border.all(color: Colors.black12),
                          image: (thumbUrl != null && thumbUrl.isNotEmpty)
                              ? DecorationImage(image: NetworkImage(thumbUrl), fit: BoxFit.cover)
                              : null,
                        ),
                        child: isPending
                            ? const Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey)))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(isPending ? "Processing Assets..." : "Archival Page",
                              style: TextStyle(fontSize: 11, color: isPending ? Colors.grey : Colors.black),
                              overflow: TextOverflow.ellipsis)),
                      IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 14),
                          onPressed: num > 1 ? () => bloc.add(ReorderPageRequested(page, -1, pages)) : null),
                      IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 14),
                          onPressed: num < pages.length ? () => bloc.add(ReorderPageRequested(page, 1, pages)) : null),
                      IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                          tooltip: "Remove from issue",
                          onPressed: () => bloc.add(RemovePageRequested(page, pages))),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOCREntitiesTab(BuildContext context, Fanzine fanzine, List<FanzinePage> pages) {
    if (fanzine.type == FanzineType.folio || fanzine.type == FanzineType.calendar) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Text("Automated OCR and Entity Extraction pipelines are not applicable for manually assembled Folios.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }

    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('images').where('usedInFanzines', arrayContains: fanzine.id).snapshots(),
        builder: (context, snapshot) {
          int rawDone = 0;
          int masterVerified = 0;
          int linkedPending = 0;

          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (data['text_raw'] != null && data['text_raw'].toString().isNotEmpty) rawDone++;
              if (data['text_corrected'] != null && data['needs_ai_cleaning'] != true) masterVerified++;
              if (data['needs_linking'] == true) linkedPending++;
            }
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Counter(label: "Raw Done", count: rawDone, color: Colors.blue),
                      _Counter(label: "Master Verified", count: masterVerified, color: Colors.green),
                      _Counter(label: "Linked Pending", count: linkedPending, color: Colors.orange),
                    ]
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                    onPressed: () => context.read<FanzineEditorBloc>().add(TriggerAiCleanRequested()),
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text("Step 2: AI Clean")
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                    onPressed: () => context.read<FanzineEditorBloc>().add(TriggerGenerateLinksRequested()),
                    icon: const Icon(Icons.link),
                    label: const Text("Step 3: Generate Links")
                ),
                const SizedBox(height: 24),
                const Divider(),
                if (fanzine.draftEntities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Text("No entities detected yet.",
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: fanzine.draftEntities.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (context, index) => _EntityRow(name: fanzine.draftEntities[index]),
                  ),
              ],
            ),
          );
        }
    );
  }
}

class _CuratorUploadTab extends StatefulWidget {
  final String fanzineId;
  final String folioTitle;
  const _CuratorUploadTab({required this.fanzineId, required this.folioTitle});
  @override
  State<_CuratorUploadTab> createState() => _CuratorUploadTabState();
}

class _CuratorUploadTabState extends State<_CuratorUploadTab> {
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
        'storagePath': path,
      });

      if (!mounted) return;

      if (is5x8) {
        context.read<FanzineEditorBloc>().add(AddExistingImageRequested(imageDocRef.id, url, width: decodedImage.width, height: decodedImage.height));
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(is5x8 ? 'full page added successfully!' : 'asset uploaded successfully!')));
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

    if (!mounted) return;

    if (result != null && result.isNotEmpty) {
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
    if (confirm == true && mounted) context.read<FanzineEditorBloc>().add(DeleteAssetRequested(imageId, isDirect));
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
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: _isUploading
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

class _Counter extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _Counter({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text("$count", style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)),
      Text(label, style: const TextStyle(fontSize: 10))
    ]);
  }
}

class _EntityRow extends StatelessWidget {
  final String name;
  const _EntityRow({required this.name});

  @override
  Widget build(BuildContext context) {
    final handle = normalizeHandle(name);
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usernames').doc(handle).snapshots(),
      builder: (context, snapshot) {
        Widget statusWidget;
        if (!snapshot.hasData) {
          statusWidget = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String linkText = '/$handle';
          if (data['isAlias'] == true) linkText = '/$handle -> /${data['redirect'] ?? 'unknown'}';
          statusWidget = Text(linkText,
              style: const TextStyle(
                  color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline));
        } else {
          statusWidget = Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
                onPressed: () => _createProfile(context, name),
                child: const Text("Create", style: TextStyle(color: Colors.green, fontSize: 11))),
            TextButton(
                onPressed: () => _createAlias(context, name),
                child: const Text("Alias", style: TextStyle(color: Colors.orange, fontSize: 11))),
          ]);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
            statusWidget,
          ]),
        );
      },
    );
  }

  Future<void> _createProfile(BuildContext context, String name) async {
    String first = name;
    String last = "";
    if (name.contains(' ')) {
      final parts = name.split(' ');
      first = parts.first;
      last = parts.sublist(1).join(' ');
    }
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Editor Widget");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final target = await showDialog<String>(
        context: context,
        builder: (c) {
          final controller = TextEditingController();
          return AlertDialog(
              title: Text("Create Alias for '$name'"),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Enter EXISTING username (target):"),
                TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
                TextButton(
                    onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))
              ]);
        });
    if (target == null || target.isEmpty) return;
    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}