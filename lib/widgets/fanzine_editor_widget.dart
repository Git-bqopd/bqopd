import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../utils/link_parser.dart';
import '../utils/shortcode_generator.dart';
import '../services/user_bootstrap.dart';
import '../services/username_service.dart';

class FanzineEditorWidget extends StatefulWidget {
  final String fanzineId;
  const FanzineEditorWidget({super.key, required this.fanzineId});

  @override
  State<FanzineEditorWidget> createState() => _FanzineEditorWidgetState();
}

class _FanzineEditorWidgetState extends State<FanzineEditorWidget> with SingleTickerProviderStateMixin {
  final TextEditingController _shortcodeController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late TabController _tabController;
  bool _isProcessing = false;
  String? _lastSyncedTitle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Listener to update UI when tab selection changes
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _shortcodeController.dispose();
    _titleController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _updateTitle(String newTitle) async {
    if (newTitle.trim().isEmpty) return;
    setState(() => _isProcessing = true);
    try {
      await _db.collection('fanzines').doc(widget.fanzineId).update({'title': newTitle.trim()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated!')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _assignMissingShortcode() async {
    setState(() => _isProcessing = true);
    try {
      final String? code = await assignShortcode(_db, 'fanzine', widget.fanzineId);
      if (code != null) {
        await _db.collection('fanzines').doc(widget.fanzineId).update({
          'shortCode': code,
          'shortCodeKey': code.toUpperCase()
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Shortcode assigned: $code')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
      int nextNum = pagesQuery.docs.isNotEmpty ? (pagesQuery.docs.first.data()['pageNumber'] ?? 0) + 1 : 1;

      final batch = _db.batch();
      final newPageRef = _db.collection('fanzines').doc(widget.fanzineId).collection('pages').doc();
      batch.set(newPageRef, {
        'imageId': imageId,
        'imageUrl': imageUrl,
        'pageNumber': nextNum,
        'status': 'ready'
      });
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transcription Pipeline Started...')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _runEntityRecognition() async {
    setState(() => _isProcessing = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('trigger_batch_entities').call({'fanzineId': widget.fanzineId});
      await FirebaseFunctions.instance.httpsCallable('finalize_fanzine_data').call({'fanzineId': widget.fanzineId});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entity Extraction & Aggregation Triggered.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rescanPdf() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rescan PDF?"),
        content: const Text("This will delete all current pages and re-extract them from the source PDF. This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("NUKE & START OVER", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('rescan_fanzine').call({'fanzineId': widget.fanzineId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescan triggered. Images will appear shortly.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('fanzines').doc(widget.fanzineId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final title = data['title'] ?? 'Untitled';
        final shortCode = data['shortCode'];
        final status = data['status'] ?? 'draft';
        final twoPage = data['twoPage'] ?? false;
        final hasSourceFile = data.containsKey('sourceFile');
        final List<String> entities = List<String>.from(data['draftEntities'] ?? []);

        if (_lastSyncedTitle != title) {
          _titleController.text = title;
          _lastSyncedTitle = title;
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // ALLOW GROWING
            children: [
              TabBar(
                controller: _tabController,
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: "Settings", icon: Icon(Icons.settings, size: 20)),
                  Tab(text: "Order", icon: Icon(Icons.format_list_numbered, size: 20)),
                  Tab(text: "OCR / Ent", icon: Icon(Icons.auto_awesome, size: 20)),
                ],
              ),
              // REPLACE TabBarView with dynamic content to allow Column expansion
              _buildTabContent(data, entities, hasSourceFile, shortCode, twoPage, status),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabContent(Map<String, dynamic> data, List<String> entities, bool hasSourceFile, String? shortCode, bool twoPage, String status) {
    switch (_tabController.index) {
      case 0:
        return _buildSettingsTab(data, hasSourceFile, shortCode, twoPage, status);
      case 1:
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PAGE ORDER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              _PageList(fanzineId: widget.fanzineId, onReorder: _reorderPage),
            ],
          ),
        );
      case 2:
        return _buildOCREntitiesTab(entities);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSettingsTab(Map<String, dynamic> data, bool hasSourceFile, String? shortCode, bool twoPage, String status) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shortcode: ${shortCode ?? 'None'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (shortCode == null)
                TextButton(
                  onPressed: _isProcessing ? null : _assignMissingShortcode,
                  child: const Text("GENERATE SHORTCODE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                )
            ],
          ),
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

          const Divider(height: 24),
          const Text('SPECIAL PAGES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
              stream: _db.collection('fanzines').doc(widget.fanzineId).collection('pages').orderBy('pageNumber').snapshots(),
              builder: (context, pagesSnap) {
                if (!pagesSnap.hasData) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()));
                final pages = pagesSnap.data!.docs;
                List<DropdownMenuItem<String?>> items = [
                  const DropdownMenuItem(value: null, child: Text("None"))
                ];
                for (var p in pages) {
                  final pData = p.data() as Map<String, dynamic>;
                  items.add(DropdownMenuItem(
                    value: p.id,
                    child: Text("Page ${pData['pageNumber']}"),
                  ));
                }

                Widget buildDropdown(String label, String field, String? currentValue) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 12))),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String?>(
                            value: items.any((i) => i.value == currentValue) ? currentValue : null,
                            items: items,
                            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                            onChanged: (val) {
                              _db.collection('fanzines').doc(widget.fanzineId).update({field: val});
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    buildDropdown("Indicia", "indiciaPageId", data['indiciaPageId']),
                    buildDropdown("Credits", "creditsPageId", data['creditsPageId']),
                    buildDropdown("Table of Contents", "tocPageId", data['tocPageId']),
                    buildDropdown("Advertiser Index", "adIndexPageId", data['adIndexPageId']),
                  ],
                );
              }
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isProcessing ? null : () => _updateTitle(_titleController.text),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
            child: _isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("SAVE SETTINGS"),
          ),
          if (hasSourceFile) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isProcessing ? null : _rescanPdf,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text("RESCAN PDF (RESET)"),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOCREntitiesTab(List<String> entities) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<QuerySnapshot>(
              stream: _db.collection('fanzines').doc(widget.fanzineId).collection('pages').snapshots(),
              builder: (context, snap) {
                int ready = 0; int queued = 0; int done = 0; int err = 0;
                if (snap.hasData) {
                  for (var doc in snap.data!.docs) {
                    final s = (doc.data() as Map)['status'];
                    if (s == 'ready') {
                      ready++;
                    } else if (s == 'queued' || s == 'entity_queued') queued++;
                    else if (s == 'transcribed' || s == 'complete' || s == 'review_needed') done++;

                    if (s == 'error') err++;
                  }
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Counter(label: "Ready", count: ready, color: Colors.blue),
                          _Counter(label: "Queued", count: queued, color: Colors.orange),
                          _Counter(label: "Done", count: done, color: Colors.green),
                        ]
                    ),
                    if (err > 0) ...[
                      const SizedBox(height: 16),
                      _ErrorBadge(label: "Errors Detected", count: err),
                    ],
                  ],
                );
              }
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
              onPressed: _isProcessing ? null : _runBatchOCR,
              icon: const Icon(Icons.bolt),
              label: const Text("Batch Transcription")
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          ElevatedButton.icon(
              onPressed: _isProcessing ? null : _runEntityRecognition,
              icon: const Icon(Icons.person_search),
              label: const Text("Run Entity Recognition")
          ),
          const SizedBox(height: 12),
          if (entities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Text("No entities detected yet.", style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: entities.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) => _EntityRow(name: entities[index]),
            ),
          const SizedBox(height: 16),
          const Text(
              "Note: Extracted text is editable directly on pages via the 'Text' social button.",
              style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center
          ),
        ],
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

class _ErrorBadge extends StatelessWidget {
  final String label;
  final int count;

  const _ErrorBadge({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red[200]!)
      ),
      child: Text("$label: $count", style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
    );
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
            TextButton(
                onPressed: () => _createProfile(context, name),
                child: const Text("Create", style: TextStyle(color: Colors.green, fontSize: 11))
            ),
            TextButton(
                onPressed: () => _createAlias(context, name),
                child: const Text("Alias", style: TextStyle(color: Colors.orange, fontSize: 11))
            ),
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
    if (name.contains(' ')) {
      final parts = name.split(' ');
      first = parts.first;
      last = parts.sublist(1).join(' ');
    }
    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Editor Widget");
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Created!")));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final target = await showDialog<String>(context: context, builder: (c) {
      final controller = TextEditingController();
      return AlertDialog(
          title: Text("Create Alias for '$name'"),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Enter EXISTING username (target):"),
                TextField(controller: controller, decoration: const InputDecoration(hintText: "e.g. julius-schwartz"))
              ]
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias"))
          ]
      );
    });
    if (target == null || target.isEmpty) return;
    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias Created!")));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
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

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
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
                        IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: num > 1 ? () => onReorder(doc, -1, docs) : null
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: num < docs.length ? () => onReorder(doc, 1, docs) : null
                        ),
                      ],
                    ),
                  );
                }
            );
          },
        );
      },
    );
  }
}