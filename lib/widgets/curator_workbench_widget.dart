import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
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
          _titleController.text = data['title'] ?? '';
          _pipelineStatus = data['processingStatus'] ?? 'idle';
        });
      }
    });
  }

  void _onTextChanged() {
    if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _listenToPages() {
    setState(() => _isLoadingPages = true);
    _db.collection('fanzines').doc(widget.fanzineId).collection('pages').orderBy('pageNumber').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _pages = snapshot.docs;
        _isLoadingPages = false;
        if (_currentPageIndex >= _pages.length) _currentPageIndex = _pages.isNotEmpty ? _pages.length - 1 : 0;
        if (!_hasUnsavedChanges && _pages.isNotEmpty) _loadPageContent(_currentPageIndex);
      });
    }, onError: (e) { if(mounted) setState(() => _isLoadingPages = false); });
  }

  void _loadPageContent(int index) {
    if (index < 0 || index >= _pages.length) return;
    final data = _pages[index].data() as Map<String, dynamic>;
    String text = data['text_processed'] ?? data['text_raw'] ?? data['text'] ?? '';

    _textController.removeListener(_onTextChanged);

    // FIX FOR FOCUS ERROR: Only update if different and not currently editing
    if (_textController.text != text) {
      _textController.text = text;
    }

    _textController.addListener(_onTextChanged);

    setState(() { _currentPageIndex = index; _hasUnsavedChanges = false; });
    _analyzeEntitiesInText();
  }

  // --- WORKFLOW ACTIONS ---

  Future<void> _runStep2_BatchOCR() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('trigger_batch_ocr').call({
        'fanzineId': widget.fanzineId,
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Processing started.')));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if(mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _runStep3_Finalize() async {
    setState(() => _isSaving = true);
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('finalize_fanzine_data').call({
        'fanzineId': widget.fanzineId,
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Finalized! Found ${result.data['entity_count'] ?? 0} entities.')));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if(mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveCurrentPage() async {
    setState(() => _isSaving = true);
    try {
      final batch = _db.batch();
      batch.update(_db.collection('fanzines').doc(widget.fanzineId), {'title': _titleController.text.trim()});
      if (_pages.isNotEmpty) {
        batch.update(_pages[_currentPageIndex].reference, {
          'text_processed': _textController.text,
          'lastEdited': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      setState(() { _isSaving = false; _hasUnsavedChanges = false; });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (e) {
      if(mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  Future<void> _reportIssue() async {
    final currentDoc = _pages[_currentPageIndex];
    final type = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text("Report Issue"),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'formatting'), child: const Text("Formatting")),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'garbled'), child: const Text("Garbled Text")),
        ],
      ),
    );
    if (type == null) return;
    await _db.collection('ocr_feedback').add({
      'fanzineId': widget.fanzineId, 'pageId': currentDoc.id, 'issue': type,
    });
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported.')));
  }

  Future<void> _analyzeEntitiesInText() async {
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
      final String handle = rawName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');
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

  Future<void> _createProfileFor(String name) async {
    try {
      await createManagedProfile(firstName: name, lastName: "", bio: "Auto-created");
      await _analyzeEntitiesInText();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile created!")));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error creating profile: $e")));
    }
  }

  Future<void> _createAliasFor(String name) async {
    final target = await showDialog<String>(
        context: context,
        builder: (c) {
          final controller = TextEditingController();
          return AlertDialog(
            title: Text("Create Alias for '$name'"),
            content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Enter EXISTING username:"), TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. mort-weisinger"))]),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")), TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))],
          );
        }
    );

    if (target == null || target.isEmpty) return;

    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      await _analyzeEntitiesInText();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias created!")));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error creating alias: $e")));
    }
  }

  Future<void> _searchEntities(String query) async {
    if (query.trim().isEmpty) { setState(() => _searchResults = []); return; }
    setState(() => _isSearching = true);
    try {
      final normalizedQuery = query.toLowerCase();
      final snapshot = await _db.collection('Users').where('username', isGreaterThanOrEqualTo: normalizedQuery).where('username', isLessThan: '${normalizedQuery}z').limit(10).get();
      final results = snapshot.docs.map((doc) {
        final data = doc.data();
        return { 'display': "${data['firstName']} ${data['lastName']}", 'username': data['username'] as String, 'id': doc.id, 'type': 'user', };
      }).toList();
      setState(() { _searchResults = results; _isSearching = false; });
    } catch (e) { if(mounted) setState(() => _isSearching = false); }
  }

  void _insertEntity(Map<String, String> entity) {
    final text = _textController.text;
    final selection = _textController.selection;
    final link = "[[${entity['display']}|${entity['type']}:${entity['id']}]]";
    String newText; int newCursorPos;
    if (selection.isValid) { newText = text.replaceRange(selection.start, selection.end, link); newCursorPos = selection.start + link.length; }
    else { newText = text + link; newCursorPos = newText.length; }
    _textController.text = newText;
    _textController.selection = TextSelection.fromPosition(TextPosition(offset: newCursorPos));
  }

  Future<void> _publishFanzine() async {
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
        'status': 'live',
        'mentionedUsers': allMentions.toList(),
        'publishedAt': FieldValue.serverTimestamp(),
      });
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fanzine Published Successfully!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if(mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error publishing: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPages) return const Center(child: CircularProgressIndicator());

    final bool hasPages = _pages.isNotEmpty;
    Map<String, dynamic> currentPageData = {};
    String imageUrl = '';
    String pageStatus = 'unknown';

    int readyCount = 0; int queuedCount = 0; int completeCount = 0; int errorCount = 0; int totalCount = _pages.length;
    for (var doc in _pages) {
      final s = doc.data() as Map<String, dynamic>;
      final status = s['status'];
      if (status == 'ready') readyCount++;
      if (status == 'queued') queuedCount++;
      if (status == 'complete' || status == 'ocr_complete') completeCount++;
      if (status == 'error') errorCount++;
    }

    if (hasPages) {
      final currentPageDoc = _pages[_currentPageIndex];
      currentPageData = currentPageDoc.data() as Map<String, dynamic>;
      imageUrl = currentPageData['imageUrl'] ?? '';
      pageStatus = currentPageData['status'] ?? 'unknown';
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;

          Widget imagePanel = Container(
            color: Colors.grey[900],
            child: hasPages && imageUrl.isNotEmpty
                ? InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_person, color: Colors.amber, size: 60),
                            const SizedBox(height: 16),
                            const Text("IMAGE ACCESS FORBIDDEN (403)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 8),
                            const Text("Your browser cannot see these images. Check Storage permissions.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
                            const SizedBox(height: 16),
                            SelectableText(imageUrl, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                          ],
                        ),
                      ),
                    );
                  },
                )
            )
                : const Center(child: Text("No Image", style: TextStyle(color: Colors.white))),
          );

          Widget rightPanel = Column(
            children: [
              Container(
                color: Colors.grey[200],
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back, size: 20), onPressed: hasPages && _currentPageIndex > 0 ? () => _loadPageContent(_currentPageIndex - 1) : null),
                    Text(hasPages ? "Page ${_currentPageIndex + 1} / $totalCount" : "-", style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.arrow_forward, size: 20), onPressed: hasPages && _currentPageIndex < _pages.length - 1 ? () => _loadPageContent(_currentPageIndex + 1) : null),
                    const Spacer(),
                    if (_hasUnsavedChanges) const Text("Unsaved ", style: TextStyle(color: Colors.orange, fontSize: 12)),
                    IconButton(icon: const Icon(Icons.save), tooltip: "Save Text", onPressed: _saveCurrentPage),
                    if (hasPages) IconButton(icon: const Icon(Icons.flag, color: Colors.orange), tooltip: "Report Issue", onPressed: _reportIssue)
                  ],
                ),
              ),

              TabBar(
                  controller: _tabController,
                  labelColor: Colors.indigo,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.indigo,
                  tabs: const [
                    Tab(text: "Pipeline", icon: Icon(Icons.account_tree_outlined, size: 16)),
                    Tab(text: "Editor", icon: Icon(Icons.edit_note, size: 16)),
                    Tab(text: "Entities", icon: Icon(Icons.people_alt, size: 16))
                  ]
              ),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text("Pipeline Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatusCounter(label: "Ready", count: readyCount, color: Colors.blue),
                              _StatusCounter(label: "Queued", count: queuedCount, color: Colors.orange),
                              _StatusCounter(label: "Done", count: completeCount, color: Colors.green),
                              if (errorCount > 0) _StatusCounter(label: "Errors", count: errorCount, color: Colors.red),
                            ],
                          ),
                          const SizedBox(height: 30),
                          const Divider(),
                          const SizedBox(height: 10),

                          ElevatedButton.icon(
                            onPressed: _isSaving || (readyCount == 0 && errorCount == 0) ? null : _runStep2_BatchOCR,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                            icon: const Icon(Icons.bolt),
                            label: Text(readyCount > 0 ? "Step 2: Run OCR on $readyCount Pages" : "Retry $errorCount Failed Pages"),
                          ),
                          const SizedBox(height: 20),

                          OutlinedButton.icon(
                            onPressed: _isSaving || completeCount == 0 ? null : _runStep3_Finalize,
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            icon: const Icon(Icons.check_circle),
                            label: const Text("Step 3: Finalize & Aggregrate Entities"),
                          ),

                          if (queuedCount > 0) ...[
                            const SizedBox(height: 20),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 8),
                            const Center(child: Text("Processing in background...", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12))),
                          ],

                          if (errorCount > 0) ...[
                            const SizedBox(height: 30),
                            const Text("Error Log", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                            const SizedBox(height: 10),
                            ..._pages.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'error').map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), border: Border.all(color: Colors.red.withOpacity(0.2)), borderRadius: BorderRadius.circular(4)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("Page ${data['pageNumber']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                                        TextButton(onPressed: () { int idx = _pages.indexOf(doc); _loadPageContent(idx); _tabController.animateTo(1); }, child: const Text("View Details", style: TextStyle(fontSize: 10))),
                                      ],
                                    ),
                                    Text(data['errorLog'] ?? 'Unknown error', style: const TextStyle(fontSize: 11, fontFamily: 'Courier')),
                                  ],
                                ),
                              );
                            }).toList(),
                          ]
                        ],
                      ),
                    ),

                    Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(labelText: 'Fanzine Title', border: UnderlineInputBorder(), isDense: true),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                          onChanged: (val) { if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true); },
                        ),
                      ),
                      if (currentPageData['status'] == 'error')
                        Container(width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.red.shade50, child: SelectableText("Error: ${currentPageData['errorLog']}", style: const TextStyle(color: Colors.red, fontSize: 11))),

                      Expanded(child: Padding(padding: const EdgeInsets.all(12.0), child: TextField(controller: _textController, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top, enabled: hasPages, decoration: const InputDecoration(hintText: "Transcribe...", border: OutlineInputBorder(), filled: true, fillColor: Colors.white), style: const TextStyle(fontFamily: 'Courier', fontSize: 14)))),
                      const Divider(height: 1),
                      SizedBox(height: 120, child: Column(children: [Padding(padding: const EdgeInsets.all(8.0), child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'Manual Search...', suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _searchResults=[])), isDense: true, border: const OutlineInputBorder()), onSubmitted: _searchEntities)), if (_searchResults.isNotEmpty) Expanded(child: ListView.builder(itemCount: _searchResults.length, itemBuilder: (c, i) => ListTile(title: Text(_searchResults[i]['display']!), onTap: () => _insertEntity(_searchResults[i]))))]))
                    ]),

                    _isValidatingEntities ? const Center(child: CircularProgressIndicator()) : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _detectedEntities.length, separatorBuilder: (c,i) => const Divider(), itemBuilder: (context, index) { final e = _detectedEntities[index]; final status = e['status']; IconData icon; Color color; String sub = ""; if (status == 'exists') { icon = Icons.check_circle; color = Colors.green; sub = "Profile Found"; } else if (status == 'alias') { icon = Icons.directions_bike; color = Colors.blue; sub = "Alias -> ${e['redirect']}"; } else { icon = Icons.warning; color = Colors.orange; sub = "No Profile Found"; } return ListTile(leading: Icon(icon, color: color), title: Text(e['name'], style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(sub), trailing: status == 'missing' ? Row(mainAxisSize: MainAxisSize.min, children: [TextButton(onPressed: () => _createProfileFor(e['name']), child: const Text("Create")), const SizedBox(width: 8), TextButton(onPressed: () => _createAliasFor(e['name']), child: const Text("Alias"))]) : null); }),
                  ],
                ),
              ),
            ],
          );

          return Column(children: [Expanded(child: isWide ? Row(children: [Expanded(child: imagePanel), Expanded(child: rightPanel)]) : Column(children: [Expanded(child: imagePanel), Expanded(child: rightPanel)])), Container(height: 50, decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [IconButton(icon: const Icon(Icons.arrow_back), onPressed: hasPages && _currentPageIndex > 0 ? () => _loadPageContent(_currentPageIndex - 1) : null), Text(hasPages ? "Page ${_currentPageIndex + 1}" : "-"), IconButton(icon: const Icon(Icons.arrow_forward), onPressed: hasPages && _currentPageIndex < _pages.length - 1 ? () => _loadPageContent(_currentPageIndex + 1) : null)]), Padding(padding: const EdgeInsets.only(right: 16), child: ElevatedButton.icon(onPressed: (_isSaving || !hasPages) ? null : _publishFanzine, icon: const Icon(Icons.publish), label: const Text("PUBLISH"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white)))]))]);
        },
      ),
    );
  }
}

class _StatusCounter extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatusCounter({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(count.toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}