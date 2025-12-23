import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/user_provider.dart';
import '../services/user_bootstrap.dart'; // For createManagedProfile
import '../services/username_service.dart'; // For createAlias, normalizeHandle

class CuratorDashboardPage extends StatefulWidget {
  const CuratorDashboardPage({super.key});

  @override
  State<CuratorDashboardPage> createState() => _CuratorDashboardPageState();
}

class _CuratorDashboardPageState extends State<CuratorDashboardPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _uploadPdf() async {
    if (_isUploading) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, // Necessary for web
      );

      if (result != null) {
        setState(() => _isUploading = true);

        PlatformFile file = result.files.first;
        Uint8List? fileBytes = file.bytes;
        String fileName = file.name;

        if (fileBytes != null) {
          // Upload to Firebase Storage
          final storageRef = FirebaseStorage.instance.ref().child('uploads/raw_pdfs/$fileName');

          // Metadata for the trigger
          final metadata = SettableMetadata(
            contentType: 'application/pdf',
            customMetadata: {
              'uploaderId': Provider.of<UserProvider>(context, listen: false).currentUserId ?? 'unknown',
              'originalName': fileName,
            },
          );

          await storageRef.putData(fileBytes, metadata);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Uploaded "$fileName". Processing started...')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _rescanFanzine(String fanzineId) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('rescan_fanzine').call({'fanzineId': fanzineId});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rescan Triggered. Scheduler bot notified.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _deleteFanzine(String fanzineId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Fanzine?"),
        content: const Text("This will remove all images and data."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFunctions.instance.httpsCallable('delete_fanzine').call({'fanzineId': fanzineId});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    if (!userProvider.isEditor) return const Scaffold(body: Center(child: Text("Access Denied.")));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Curator Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "Review Fanzines"), Tab(text: "Entities")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          PageWrapper(maxWidth: 1400, child: _buildReviewTab()),
          PageWrapper(maxWidth: 1000, child: _buildEntitiesList()),
        ],
      ),
    );
  }

  Widget _buildReviewTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- UPLOAD AREA ---
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadPdf,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                icon: _isUploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file),
                label: Text(_isUploading ? "Uploading..." : "Upload PDF"),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  "Upload PDFs to ingest. They will appear in the list below once processed.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // --- LIST ---
        Expanded(child: _buildDraftsList()),
      ],
    );
  }

  Widget _buildDraftsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fanzines')
          .where('status', whereIn: ['draft', 'working'])
          .orderBy('creationDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("No drafts to review. Upload a PDF to start."));

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('Fanzine Title')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Errors (OCR/Ent)')),
              DataColumn(label: Text('Actions')),
            ],
            rows: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final id = doc.id;

              return DataRow(cells: [
                DataCell(
                    SizedBox(
                      width: 250,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['title'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          Text("ID: $id", style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
                        ],
                      ),
                    )
                ),
                DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(data['processingStatus'] ?? 'idle', style: const TextStyle(fontSize: 12)),
                    )
                ),
                DataCell(_ErrorCounter(fanzineId: id)),
                DataCell(
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.blue),
                          tooltip: "Rescan",
                          onPressed: () => _rescanFanzine(id),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => context.push('/workbench/$id'),
                          child: const Text("Workbench"),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: "Delete",
                          onPressed: () => _deleteFanzine(id),
                        ),
                      ],
                    )
                ),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildEntitiesList() {
    // 1. Get ALL draft AND working fanzines to aggregate entities
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fanzines')
          .where('status', whereIn: ['draft', 'working'])
          .snapshots(),
      builder: (context, fanzineSnapshot) {
        if (fanzineSnapshot.hasError) return Center(child: Text("Error: ${fanzineSnapshot.error}"));
        if (!fanzineSnapshot.hasData) return const Center(child: CircularProgressIndicator());

        // Aggregate counts: { "Julius Schwartz": 5, "Gardner Fox": 2 }
        final Map<String, int> entityCounts = {};
        for (var doc in fanzineSnapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final entities = List<String>.from(data['draftEntities'] ?? []);
          for (var name in entities) {
            entityCounts[name] = (entityCounts[name] ?? 0) + 1;
          }
        }

        if (entityCounts.isEmpty) {
          return const Center(child: Text("No entities found in current drafts."));
        }

        // Sort by Count (Descending), then Alphabetical
        final sortedNames = entityCounts.keys.toList()
          ..sort((a, b) {
            int countCompare = entityCounts[b]!.compareTo(entityCounts[a]!);
            if (countCompare != 0) return countCompare;
            return a.compareTo(b);
          });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sortedNames.length,
          separatorBuilder: (c, i) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final name = sortedNames[index];
            final count = entityCounts[name]!;

            return _EntityRow(name: name, count: count);
          },
        );
      },
    );
  }
}

class _EntityRow extends StatelessWidget {
  final String name;
  final int count;

  const _EntityRow({required this.name, required this.count});

  @override
  Widget build(BuildContext context) {
    // Generate the handle exactly as our bootstrap logic does now
    // (lowercase, alphanumeric+hyphen only, no trailing hyphen)
    final handle = normalizeHandle(name);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usernames').doc(handle).snapshots(),
      builder: (context, snapshot) {
        // --- Widget States ---
        Widget statusWidget;

        if (!snapshot.hasData) {
          statusWidget = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snapshot.data!.exists) {
          // EXISTS: Show Link
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String linkText = '/$handle';

          if (data['isAlias'] == true) {
            final redirect = data['redirect'] ?? 'unknown';
            linkText = '/$handle -> /$redirect';
          }

          statusWidget = InkWell(
            onTap: () => context.go('/$handle'),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                linkText,
                style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline
                ),
              ),
            ),
          );
        } else {
          // MISSING: Show Create Buttons
          statusWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _createProfile(context, name),
                child: const Text("Create", style: TextStyle(color: Colors.green)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _createAlias(context, name),
                child: const Text("Alias", style: TextStyle(color: Colors.orange)),
              ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(count.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              Expanded(
                child: Text(name, style: const TextStyle(fontSize: 16)),
              ),
              statusWidget,
            ],
          ),
        );
      },
    );
  }

  Future<void> _createProfile(BuildContext context, String name) async {
    // Basic splitting logic to handle "Name Surname"
    String first = name;
    String last = "";

    if (name.contains(' ')) {
      final parts = name.split(' ');
      first = parts.first;
      last = parts.sublist(1).join(' ');
    }

    try {
      await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from dashboard");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Created!")));
      // Force rebuild? The FutureBuilder will re-run if parent rebuilds, but local state might stick.
      (context as Element).markNeedsBuild();
    } catch (e) {
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
              TextButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text("Create Alias")),
            ],
          );
        }
    );

    if (target == null || target.isEmpty) return;

    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alias Created!")));
      (context as Element).markNeedsBuild();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}

class _ErrorCounter extends StatelessWidget {
  final String fanzineId;

  const _ErrorCounter({required this.fanzineId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: Text("-"));

        int ocrErrors = 0;
        int entErrors = 0;

        for (var doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          if (d['status'] == 'error' || (d['error_ocr'] ?? 0) > 0) ocrErrors++;
          if ((d['error_entity_id'] ?? 0) > 0) entErrors++;
        }

        if (ocrErrors == 0 && entErrors == 0) return const Text("OK", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold));

        return Text(
            "OCR: $ocrErrors | Ent: $entErrors",
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)
        );
      },
    );
  }
}