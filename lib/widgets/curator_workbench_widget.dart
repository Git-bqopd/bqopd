import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/link_parser.dart';
import '../services/user_bootstrap.dart';
import '../services/username_service.dart';

class CuratorWorkbenchWidget extends StatefulWidget {
  final String fanzineId;

  const CuratorWorkbenchWidget({super.key, required this.fanzineId});

  @override
  State<CuratorWorkbenchWidget> createState() => _CuratorWorkbenchWidgetState();
}

class _CuratorWorkbenchWidgetState extends State<CuratorWorkbenchWidget> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late TabController _tabController;

  List<DocumentSnapshot> _pages = [];
  int _currentPageIndex = 0;
  bool _isLoadingPages = true;

  // Current page engagement data
  int _currentPageLikes = 0;
  int _currentPageComments = 0;

  String _currentImageUrl = '';
  bool _isLoadingImage = false;

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  bool _isSearching = false;

  List<Map<String, dynamic>> _detectedEntities = [];
  bool _isValidatingEntities = false;

  String _pipelineStatus = 'idle';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _listenToPages();
    _listenToFanzineStatus();
    _textController.addListener(_onTextChanged);
  }

  Future<void> _listenToFanzineStatus() async {
    _db.collection('fanzines').doc(widget.fanzineId).snapshots().listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          if (!_hasUnsavedChanges && _titleController.text.isEmpty) {
            _titleController.text = data['title'] ?? '';
          }
          _pipelineStatus = data['processingStatus'] ?? 'idle';
        });
      }
    });
  }

  void _onTextChanged() { if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true); }

  @override
  void dispose() { _textController.dispose(); _titleController.dispose(); _searchController.dispose(); _tabController.dispose(); super.dispose(); }

  void _listenToPages() {
    setState(() => _isLoadingPages = true);
    _db.collection('fanzines').doc(widget.fanzineId).collection('pages').orderBy('pageNumber').snapshots().listen((snapshot) {
      if (!mounted) return;
      String? currentId;
      if (_pages.isNotEmpty && _currentPageIndex < _pages.length) currentId = _pages[_currentPageIndex].id;
      setState(() {
        _pages = snapshot.docs;
        _isLoadingPages = false;
        if (currentId != null) {
          final idx = _pages.indexWhere((doc) => doc.id == currentId);
          if (idx != -1) _currentPageIndex = idx;
        }
        if (_currentPageIndex >= _pages.length) _currentPageIndex = _pages.isNotEmpty ? _pages.length - 1 : 0;
        if (!_hasUnsavedChanges && _pages.isNotEmpty) _loadPageContent(_currentPageIndex);
      });
    });
  }

  void _loadPageContent(int index) {
    if (index < 0 || index >= _pages.length) return;
    final data = _pages[index].data() as Map<String, dynamic>;
    String text = data['text_processed'] ?? data['text_raw'] ?? data['text'] ?? '';

    // Updated to handle Engagement Logic metrics
    _currentPageLikes = data['likeCount'] ?? 0;
    _currentPageComments = data['commentCount'] ?? 0;

    _textController.removeListener(_onTextChanged);
    _textController.text = text;
    _textController.addListener(_onTextChanged);
    setState(() { _currentPageIndex = index; _hasUnsavedChanges = false; _isLoadingImage = true; });
    _analyzeEntitiesInText();
    _refreshImageUrl(data);
  }

  Future<void> _refreshImageUrl(Map<String, dynamic> data) async {
    String url = data['imageUrl'] ?? '';
    final storagePath = data['storagePath'];
    if (storagePath != null && storagePath.toString().isNotEmpty) {
      try { url = await FirebaseStorage.instance.ref(storagePath).getDownloadURL(); } catch (_) {}
    }
    if (mounted) setState(() { _currentImageUrl = url; _isLoadingImage = false; });
  }

  Future<void> _runStep2_BatchOCR() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('trigger_batch_ocr').call({'fanzineId': widget.fanzineId});
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OCR Dispatching...')));
    } catch (e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if(mounted) setState(() => _isSaving = false); }
  }

  Future<void> _runStep3_Finalize() async {
    setState(() => _isSaving = true);
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('finalize_fanzine_data').call({'fanzineId': widget.fanzineId});
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Found ${result.data['entity_count'] ?? 0} entities.')));
    } catch (e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if(mounted) setState(() => _isSaving = false); }
  }

  Future<void> _saveCurrentPage() async {
    setState(() => _isSaving = true);
    try {
      final batch = _db.batch();
      batch.update(_db.collection('fanzines').doc(widget.fanzineId), {'title': _titleController.text.trim(), 'pageCount': _pages.length});
      if (_pages.isNotEmpty) batch.update(_pages[_currentPageIndex].reference, {'text_processed': _textController.text, 'lastEdited': FieldValue.serverTimestamp()});
      await batch.commit();
      setState(() { _isSaving = false; _hasUnsavedChanges = false; });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (e) { if(mounted) { setState(() => _isSaving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e'))); } }
  }

  Future<void> _analyzeEntitiesInText() async {
    if (!mounted) return;
    setState(() => _isValidatingEntities = true);
    final text = _textController.text;
    final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
    final matches = regex.allMatches(text);
    final List<Map<String, dynamic>> results = [];
    final Set<String> processed = {};

    for (final match in matches) {
      final String rawName = match.group(1) ?? '';
      if (rawName.isEmpty || processed.contains(rawName)) continue;
      processed.add(rawName);
      final String handle = normalizeHandle(rawName);
      String status = 'unknown'; String? targetId; String? redirect;

      final doc = await _db.collection('usernames').doc(handle).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (data.containsKey('redirect')) { status = 'alias'; redirect = data['redirect']; }
        else { status = 'exists'; targetId = data['uid']; }
      } else { status = 'missing'; }
      results.add({ 'name': rawName, 'handle': handle, 'status': status, 'targetId': targetId, 'redirect': redirect });
    }
    if (mounted) setState(() { _detectedEntities = results; _isValidatingEntities = false; });
  }

  void _insertEntity(Map<String, String> entity) {
    final text = _textController.text;
    final selection = _textController.selection;
    final link = "[[${entity['display']}|user:${entity['id']}]]";
    String newText = selection.isValid ? text.replaceRange(selection.start, selection.end, link) : text + link;
    _textController.text = newText;
    _textController.selection = TextSelection.fromPosition(TextPosition(offset: (selection.isValid ? selection.start : text.length) + link.length));
  }

  Future<void> _softPublish() async {
    if (_hasUnsavedChanges) await _saveCurrentPage();
    setState(() => _isSaving = true);
    try {
      final allMentions = <String>{};
      final pagesSnap = await _db.collection('fanzines').doc(widget.fanzineId).collection('pages').get();
      for (final doc in pagesSnap.docs) {
        final text = doc.data()['text_processed'] ?? '';
        final mentions = await LinkParser.parseMentions(text);
        allMentions.addAll(mentions);
      }
      await _db.collection('fanzines').doc(widget.fanzineId).update({
        'status': 'working',
        'mentionedUsers': allMentions.toList(),
        'publishedAt': FieldValue.serverTimestamp(),
        'isSoftPublished': true,
        'pageCount': pagesSnap.docs.length,
      });
      setState(() => _isSaving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Soft Publish Complete!')));
    } catch (e) { setState(() => _isSaving = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPages) return const Center(child: CircularProgressIndicator());
    final bool hasPages = _pages.isNotEmpty;
    int readyCount = 0; int queuedCount = 0; int completeCount = 0; int errorCount = 0;
    for (var doc in _pages) {
      final s = doc.data() as Map<String, dynamic>;
      final status = s['status'];
      if (status == 'ready') readyCount++; else if (status == 'queued') queuedCount++; else if (status == 'ocr_complete' || status == 'complete') completeCount++; else if (status == 'error') errorCount++;
    }

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        Widget imagePanel = Container(color: Colors.grey[900], child: _isLoadingImage ? const Center(child: CircularProgressIndicator(color: Colors.white)) : (hasPages ? InteractiveViewer(child: Image.network(_currentImageUrl, fit: BoxFit.contain)) : const Center(child: Text("No Image", style: TextStyle(color: Colors.white)))));
        Widget rightPanel = Column(children: [
          Container(color: Colors.grey[200], padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: hasPages && _currentPageIndex > 0 ? () => _loadPageContent(_currentPageIndex - 1) : null),
            Text("Page ${_currentPageIndex + 1} / ${_pages.length}"),
            IconButton(icon: const Icon(Icons.arrow_forward), onPressed: hasPages && _currentPageIndex < _pages.length - 1 ? () => _loadPageContent(_currentPageIndex + 1) : null),

            // --- ENGAGEMENT METRICS (For Curator Monitoring) ---
            const SizedBox(width: 16),
            Icon(Icons.favorite, size: 14, color: Colors.red[300]),
            const SizedBox(width: 4),
            Text("$_currentPageLikes", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Icon(Icons.comment, size: 14, color: Colors.blueGrey[300]),
            const SizedBox(width: 4),
            Text("$_currentPageComments", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),

            const Spacer(),
            IconButton(icon: const Icon(Icons.save), onPressed: _saveCurrentPage)
          ])),
          TabBar(controller: _tabController, tabs: const [Tab(text: "Pipeline"), Tab(text: "Editor"), Tab(text: "Entities")]),
          Expanded(child: TabBarView(controller: _tabController, children: [
            SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text("Pipeline Status", style: TextStyle(fontWeight: FontWeight.bold)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Counter(label: "Ready", count: readyCount, color: Colors.blue),
                _Counter(label: "Queued", count: queuedCount, color: Colors.orange),
                _Counter(label: "Done", count: completeCount, color: Colors.green),
              ]),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _runStep2_BatchOCR, child: const Text("Run Step 2: Batch OCR")),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _runStep3_Finalize, child: const Text("Run Step 3: Finalize")),
            ])),
            Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _textController, maxLines: null, expands: true, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Transcribe..."))),
            ListView.separated(padding: const EdgeInsets.all(16), itemCount: _detectedEntities.length, separatorBuilder: (c,i) => const Divider(), itemBuilder: (c, i) {
              final e = _detectedEntities[i];
              return ListTile(title: Text(e['name']), subtitle: Text(e['status']));
            })
          ]))
        ]);

        return Column(children: [
          Expanded(child: isWide ? Row(children: [Expanded(child: imagePanel), Expanded(child: rightPanel)]) : Column(children: [Expanded(child: imagePanel), Expanded(child: rightPanel)])),
          Container(height: 50, color: Colors.white, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ElevatedButton(onPressed: _softPublish, style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white), child: const Text("Soft Publish")),
            const SizedBox(width: 10),
            ElevatedButton(onPressed: () => _db.collection('fanzines').doc(widget.fanzineId).update({'status': 'live'}), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text("Mark Live")),
            const SizedBox(width: 16),
          ]))
        ]);
      }),
    );
  }
}

class _Counter extends StatelessWidget {
  final String label; final int count; final Color color;
  const _Counter({required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) { return Column(children: [Text("$count", style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)), Text(label, style: const TextStyle(fontSize: 10))]); }
}