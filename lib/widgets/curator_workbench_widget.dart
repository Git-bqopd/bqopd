import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
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
  final TextEditingController _titleController = TextEditingController(); // Added title controller
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  bool _isSearching = false;
  bool _isUploading = false;

  List<Map<String, dynamic>> _detectedEntities = [];
  bool _isValidatingEntities = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _listenToPages();
    _fetchFanzineTitle(); // Fetch title
    _textController.addListener(_onTextChanged);
  }

  Future<void> _fetchFanzineTitle() async {
    try {
      final doc = await _db.collection('fanzines').doc(widget.fanzineId).get();
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        _titleController.text = data['title'] ?? '';
      }
    } catch (e) {
      print("Error fetching title: $e");
    }
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
    if (_textController.text != text) _textController.text = text;
    _textController.addListener(_onTextChanged);

    setState(() { _currentPageIndex = index; _hasUnsavedChanges = false; });

    // Auto-analyze entities when loading page
    _analyzeEntitiesInText();
  }

  Future<void> _saveCurrentPage() async {
    setState(() => _isSaving = true);
    try {
      final batch = _db.batch();

      // 1. Update Fanzine Title
      batch.update(_db.collection('fanzines').doc(widget.fanzineId), {
        'title': _titleController.text.trim(),
      });

      // 2. Update Page Content (if pages exist)
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
      setState(() => _isSaving = false);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  Future<void> _reportIssue() async {
    final currentDoc = _pages[_currentPageIndex];
    final data = currentDoc.data() as Map<String, dynamic>;

    final type = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text("Report Issue with OCR"),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'column_formatting'), child: const Text("Column / Line Break Issues")),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'missing_text'), child: const Text("Missed Text / Blocks")),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'garbled'), child: const Text("Garbled / Nonsense Output")),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'other'), child: const Text("Other")),
        ],
      ),
    );

    if (type == null) return;

    try {
      await _db.collection('ocr_feedback').add({
        'fanzineId': widget.fanzineId,
        'pageId': currentDoc.id,
        'pageNumber': data['pageNumber'],
        'issueType': type,
        'original_text_raw': data['text_raw'],
        'current_text_processed': _textController.text,
        'imageUrl': data['imageUrl'],
        'reportedAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report logged!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
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
      String status = 'unknown';
      String? targetId;
      String? redirect;

      final doc = await _db.collection('usernames').doc(handle).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (data.containsKey('redirect')) {
          status = 'alias';
          redirect = data['redirect'];
        } else {
          status = 'exists';
          targetId = data['uid'];
        }
      } else {
        status = 'missing';
      }

      results.add({
        'name': rawName,
        'handle': handle,
        'status': status,
        'targetId': targetId,
        'redirect': redirect,
      });
    }

    if (mounted) setState(() { _detectedEntities = results; _isValidatingEntities = false; });
  }

  Future<void> _createProfileFor(String name) async {
    final parts = name.split(' ');
    final first = parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created");
      await _analyzeEntitiesInText();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile created!")));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _addPage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => _isUploading = true);
    try {
      final Uint8List fileData = await image.readAsBytes();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final String filePath = 'fanzines/${widget.fanzineId}/pages/$fileName';
      final Reference storageRef = FirebaseStorage.instance.ref().child(filePath);
      final UploadTask uploadTask = storageRef.putData(fileData, SettableMetadata(contentType: 'image/${p.extension(fileName).replaceAll('.', '')}'));
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      int newPageNumber = 1;
      if (_pages.isNotEmpty) {
        final lastData = _pages.last.data() as Map<String, dynamic>;
        newPageNumber = (lastData['pageNumber'] ?? 0) + 1;
      }
      await _db.collection('fanzines').doc(widget.fanzineId).collection('pages').add({
        'imageUrl': downloadUrl,
        'pageNumber': newPageNumber,
        'text_processed': '', 'text_raw': '',
        'uploadedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page Added!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload Error: $e')));
    } finally {
      setState(() => _isUploading = false);
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
    } catch (e) { setState(() => _isSearching = false); }
  }

  void _insertEntity(Map<String, String> entity) {
    final text = _textController.text;
    final selection = _textController.selection;
    final link = "[[${entity['display']}|${entity['type']}:${entity['id']}]]";
    String newText;
    int newCursorPos;
    if (selection.isValid) {
      newText = text.replaceRange(selection.start, selection.end, link);
      newCursorPos = selection.start + link.length;
    } else {
      newText = text + link;
      newCursorPos = newText.length;
    }
    _textController.text = newText;
    _textController.selection = TextSelection.fromPosition(TextPosition(offset: newCursorPos));
  }

  Future<void> _publishFanzine() async {
    if (_hasUnsavedChanges) await _saveCurrentPage();
    setState(() => _isSaving = true);
    try {
      final Set<String> allMentions = {};
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
      setState(() => _isSaving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error publishing: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPages) return const Center(child: CircularProgressIndicator());
    final bool hasPages = _pages.isNotEmpty;
    Map<String, dynamic> currentPageData = {};
    String imageUrl = '';
    if (hasPages) {
      final currentPageDoc = _pages[_currentPageIndex];
      currentPageData = currentPageDoc.data() as Map<String, dynamic>;
      imageUrl = currentPageData['imageUrl'] ?? '';
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          Widget imagePanel = Container(
            color: Colors.grey[900],
            child: hasPages && imageUrl.isNotEmpty
                ? InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: Image.network(imageUrl, fit: BoxFit.contain))
                : const Center(child: Text("No Image", style: TextStyle(color: Colors.white))),
          );

          Widget rightPanel = Column(
            children: [
              Container(
                color: Colors.grey[200],
                child: Column(
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: [Text(hasPages ? "Page ${_currentPageIndex + 1}" : "-", style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(), if (_hasUnsavedChanges) const Text("Unsaved ", style: TextStyle(color: Colors.orange, fontSize: 12)), IconButton(icon: const Icon(Icons.save), onPressed: _saveCurrentPage), if (hasPages) IconButton(icon: const Icon(Icons.flag, color: Colors.orange), onPressed: _reportIssue)])),
                    TabBar(controller: _tabController, labelColor: Colors.indigo, unselectedLabelColor: Colors.grey, indicatorColor: Colors.indigo, tabs: const [Tab(text: "Editor", icon: Icon(Icons.edit_note, size: 16)), Tab(text: "Entities", icon: Icon(Icons.people_alt, size: 16))]),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    Column(children: [
                      // NEW TITLE FIELD
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Fanzine Title',
                            border: UnderlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                          onChanged: (val) {
                            if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
                          },
                        ),
                      ),
                      if (currentPageData.containsKey('error')) Container(width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.red.shade100, child: SelectableText("OCR Error: ${currentPageData['error']}", style: TextStyle(color: Colors.red.shade900, fontSize: 12))), Expanded(child: Padding(padding: const EdgeInsets.all(12.0), child: TextField(controller: _textController, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top, enabled: hasPages, decoration: const InputDecoration(hintText: "Transcribe...", border: OutlineInputBorder(), filled: true, fillColor: Colors.white), style: const TextStyle(fontFamily: 'Courier', fontSize: 14)))), const Divider(height: 1), SizedBox(height: 120, child: Column(children: [Padding(padding: const EdgeInsets.all(8.0), child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'Manual Search...', suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _searchResults=[])), isDense: true, border: const OutlineInputBorder()), onSubmitted: _searchEntities)), if (_searchResults.isNotEmpty) Expanded(child: ListView.builder(itemCount: _searchResults.length, itemBuilder: (c, i) => ListTile(title: Text(_searchResults[i]['display']!), onTap: () => _insertEntity(_searchResults[i]))))]))]),
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