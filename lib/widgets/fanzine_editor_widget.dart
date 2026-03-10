import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../utils/link_parser.dart';
import '../services/user_bootstrap.dart';
import '../services/username_service.dart';

class FanzineEditorWidget extends StatefulWidget {
  final String fanzineId;
  const FanzineEditorWidget({super.key, required this.fanzineId});

  @override
  State<FanzineEditorWidget> createState() => _FanzineEditorWidgetState();
}

class _FanzineEditorWidgetState extends State<FanzineEditorWidget> {
  final TextEditingController _shortcodeController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isProcessing = false;
  String? _lastSyncedTitle;

  @override
  void dispose() {
    _shortcodeController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _updateTitle(String newTitle) async {
    if (newTitle.trim().isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      await _db.collection('fanzines').doc(widget.fanzineId).update({'title': newTitle.trim()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fanzine title updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating title: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _addPage() async {
    final shortcode = _shortcodeController.text.trim();
    if (shortcode.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final imageQuery = await _db.collection('images').where('shortCode', isEqualTo: shortcode).limit(1).get();
      if (imageQuery.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image not found.')));
        return;
      }

      final imageDoc = imageQuery.docs.first;
      final imageId = imageDoc.id;
      final imageUrl = imageDoc.data()['fileUrl'];

      final pagesQuery = await _db.collection('fanzines').doc(widget.fanzineId).collection('pages').orderBy('pageNumber', descending: true).limit(1).get();
      int nextNum = 1;
      if (pagesQuery.docs.isNotEmpty) nextNum = (pagesQuery.docs.first.data()['pageNumber'] ?? 0) + 1;

      final batch = _db.batch();
      final newPageRef = _db.collection('fanzines').doc(widget.fanzineId).collection('pages').doc();
      batch.set(newPageRef, {'imageId': imageId, 'imageUrl': imageUrl, 'pageNumber': nextNum});
      batch.update(_db.collection('images').doc(imageId), {'usedInFanzines': FieldValue.arrayUnion([widget.fanzineId])});
      await batch.commit();

      _shortcodeController.clear();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _reorderPage(DocumentSnapshot doc, int delta, List<DocumentSnapshot> allPages) async {
    final int currentPos = doc.get('pageNumber');
    final int targetPos = currentPos + delta;
    if (targetPos < 1 || targetPos > allPages.length) return;

    final targetDoc = allPages.firstWhere((p) => p.get('pageNumber') == targetPos);
    final batch = _db.batch();
    batch.update(doc.reference, {'pageNumber': targetPos});
    batch.update(targetDoc.reference, {'pageNumber': currentPos});
    await batch.commit();
  }

  Future<void> _toggleStatus(String currentStatus) async {
    final newStatus = currentStatus == 'live' ? 'working' : 'live';
    await _db.collection('fanzines').doc(widget.fanzineId).update({'status': newStatus});
  }

  Future<void> _updateTwoPage(bool val) async {
    await _db.collection('fanzines').doc(widget.fanzineId).update({'twoPage': val});
  }

  Future<void> _softPublish() async {
    setState(() => _isProcessing = true);
    try {
      final allMentions = <String>{};
      final pagesSnap = await _db.collection('fanzines').doc(widget.fanzineId).collection('pages').get();
      for (final doc in pagesSnap.docs) {
        final data = doc.data();
        final imageId = data['imageId'];
        if (imageId != null) {
          final imgDoc = await _db.collection('images').doc(imageId).get();
          final text = imgDoc.data()?['text'] ?? '';
          final mentions = await LinkParser.parseMentions(text);
          allMentions.addAll(mentions);
        }
      }
      await _db.collection('fanzines').doc(widget.fanzineId).update({
        'mentionedUsers': allMentions.toList(),
        'publishedAt': FieldValue.serverTimestamp(),
        'isSoftPublished': true,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Soft Published!')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _runBatchOCR() async {
    setState(() => _isProcessing = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('trigger_batch_ocr').call({'fanzineId': widget.fanzineId});
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Batch OCR Dispatching...')));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _runEntityRecognition() async {
    setState(() => _isProcessing = true);
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('finalize_fanzine_data').call({'fanzineId': widget.fanzineId});
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Entity Recognition complete. Found ${result.data['entity_count'] ?? 0} items.')));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: StreamBuilder<DocumentSnapshot>(
        stream: _db.collection('fanzines').doc(widget.fanzineId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final title = data['title'] ?? 'Untitled';
          final shortCode = data['shortCode'] ?? 'None';
          final status = data['status'] ?? 'draft';
          final twoPage = data['twoPage'] ?? false;
          final List<String> entities = List<String>.from(data['draftEntities'] ?? []);

          if (_lastSyncedTitle != title) {
            _titleController.text = title;
            _lastSyncedTitle = title;
          }

          return Container(
            height: 480, // Height increased for nested tabs
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(
              children: [
                TabBar(
                  labelColor: Theme.of(context).primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const [
                    Tab(text: "Settings", icon: Icon(Icons.settings, size: 20)),
                    Tab(text: "Order", icon: Icon(Icons.format_list_numbered, size: 20)),
                    Tab(text: "OCR / Ent", icon: Icon(Icons.auto_awesome, size: 20)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // --- SETTINGS TAB ---
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _titleController,
                              onSubmitted: _updateTitle,
                              decoration: const InputDecoration(labelText: 'Fanzine Name', isDense: true, border: OutlineInputBorder(), helperText: "Press enter or click SAVE below"),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            Row(children: [
                              Expanded(child: TextField(controller: _shortcodeController, decoration: const InputDecoration(hintText: 'Paste image shortcode', isDense: true, border: OutlineInputBorder()))),
                              const SizedBox(width: 8),
                              ElevatedButton(onPressed: _isProcessing ? null : _addPage, child: const Text('Add Page')),
                            ]),
                            const SizedBox(height: 12),
                            Text('Shortcode: $shortCode', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              const Text('Has two page spread view', style: TextStyle(fontSize: 12)),
                              Switch(value: twoPage, onChanged: (val) => _updateTwoPage(val)),
                            ]),
                            const Divider(height: 24),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                Text(status.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: status == 'live' ? Colors.green : Colors.orange)),
                              ]),
                              Row(children: [
                                TextButton(onPressed: _softPublish, child: const Text('Soft Publish')),
                                Switch(value: status == 'live', onChanged: (_) => _toggleStatus(status)),
                                const Text('Live', style: TextStyle(fontSize: 12)),
                              ])
                            ]),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _isProcessing ? null : () => _updateTitle(_titleController.text),
                              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                              child: _isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("SAVE SETTINGS"),
                            ),
                          ],
                        ),
                      ),
                      // --- PAGINATION TAB ---
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PAGE ORDER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Expanded(child: SingleChildScrollView(child: _PageList(fanzineId: widget.fanzineId, onReorder: _reorderPage))),
                          ],
                        ),
                      ),
                      // --- OCR & ENTITIES NESTED TABS ---
                      DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            const TabBar(
                              labelColor: Colors.black,
                              unselectedLabelColor: Colors.grey,
                              indicatorColor: Colors.black54,
                              tabs: [
                                Tab(text: "Batch OCR"),
                                Tab(text: "Batch Entity Recognition"),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  // SUB-TAB 1: BATCH OCR
                                  SingleChildScrollView(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        StreamBuilder<QuerySnapshot>(
                                            stream: _db.collection('fanzines').doc(widget.fanzineId).collection('pages').snapshots(),
                                            builder: (context, snap) {
                                              int ready = 0; int queued = 0; int done = 0;
                                              if (snap.hasData) {
                                                for (var doc in snap.data!.docs) {
                                                  final s = (doc.data() as Map)['status'];
                                                  if (s == 'ready') ready++; else if (s == 'queued') queued++; else if (s == 'ocr_complete' || s == 'complete') done++;
                                                }
                                              }
                                              return Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                                                _Counter(label: "Ready", count: ready, color: Colors.blue),
                                                _Counter(label: "Queued", count: queued, color: Colors.orange),
                                                _Counter(label: "Done", count: done, color: Colors.green),
                                              ]);
                                            }
                                        ),
                                        const SizedBox(height: 24),
                                        ElevatedButton.icon(onPressed: _isProcessing ? null : _runBatchOCR, icon: const Icon(Icons.bolt), label: const Text("Batch OCR")),
                                        const SizedBox(height: 16),
                                        const Text("Note: Extracted text is editable directly on pages via the 'Text' social button.", style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                                      ],
                                    ),
                                  ),
                                  // SUB-TAB 2: BATCH ENTITY RECOGNITION
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: ElevatedButton.icon(onPressed: _isProcessing ? null : _runEntityRecognition, icon: const Icon(Icons.person_search), label: const Text("Batch Entity Recognition")),
                                      ),
                                      Expanded(
                                        child: entities.isEmpty
                                            ? const Center(child: Text("No entities detected yet.", style: TextStyle(color: Colors.grey, fontSize: 12)))
                                            : ListView.separated(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          itemCount: entities.length,
                                          separatorBuilder: (c, i) => const Divider(height: 1),
                                          itemBuilder: (context, index) => _EntityRow(name: entities[index]),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final String label; final int count; final Color color;
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
          statusWidget = Text(linkText, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline));
        } else {
          statusWidget = Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => _createProfile(context, name), child: const Text("Create", style: TextStyle(color: Colors.green, fontSize: 11))),
            TextButton(onPressed: () => _createAlias(context, name), child: const Text("Alias", style: TextStyle(color: Colors.orange, fontSize: 11))),
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
    String first = name; String last = "";
    if (name.contains(' ')) { final parts = name.split(' '); first = parts.first; last = parts.sublist(1).join(' '); }
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Editor Widget");
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final target = await showDialog<String>(context: context, builder: (c) {
      final controller = TextEditingController();
      return AlertDialog(title: Text("Create Alias for '$name'"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Enter EXISTING username (target):"), TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")), TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))]);
    });
    if (target == null || target.isEmpty) return;
    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
  }
}

class _PageList extends StatelessWidget {
  final String fanzineId;
  final Function(DocumentSnapshot, int, List<DocumentSnapshot>) onReorder;
  const _PageList({required this.fanzineId, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').orderBy('pageNumber').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Text('No pages added.', style: TextStyle(color: Colors.grey, fontSize: 12));
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final num = data['pageNumber'] ?? 0;
            final imageId = data['imageId'] ?? '...';
            return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('images').doc(imageId).get(),
                builder: (context, imgSnap) {
                  final imgTitle = (imgSnap.data?.data() as Map?)?['title'] ?? 'Untitled Page';
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5))),
                    child: Row(
                      children: [
                        Text('$num.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(imgTitle, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                        IconButton(icon: const Icon(Icons.arrow_upward, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: num > 1 ? () => onReorder(doc, -1, docs) : null),
                        const SizedBox(width: 4),
                        IconButton(icon: const Icon(Icons.arrow_downward, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: num < docs.length ? () => onReorder(doc, 1, docs) : null),
                      ],
                    ),
                  );
                }
            );
          }).toList(),
        );
      },
    );
  }
}