import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/user_provider.dart';
import '../services/user_bootstrap.dart';

class CuratorDashboardPage extends StatefulWidget {
  const CuratorDashboardPage({super.key});

  @override
  State<CuratorDashboardPage> createState() => _CuratorDashboardPageState();
}

class _CuratorDashboardPageState extends State<CuratorDashboardPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _selectedEntities = {};
  bool _isCreatingProfiles = false;

  // Track which fanzines contain which entities to update them later
  final Map<String, Set<String>> _entityToFanzineIds = {};

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

  Future<void> _rescanFanzine(BuildContext context, String fanzineId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Rescan Fanzine?"),
        content: const Text("This will delete current pages and re-run OCR with the latest settings. Manual edits will be lost."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Rescan")),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Starting Rescan...")));

    try {
      await FirebaseFunctions.instance.httpsCallable('rescan_fanzine').call({
        'fanzineId': fanzineId,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rescan Complete! Data processing started.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _deleteFanzine(BuildContext context, String fanzineId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Fanzine?"),
        content: const Text("This action cannot be undone. It will remove the fanzine and all its pages/images."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("DELETE", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFunctions.instance.httpsCallable('delete_fanzine').call({
        'fanzineId': fanzineId,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _createSelectedProfiles() async {
    if (_selectedEntities.isEmpty) return;

    setState(() => _isCreatingProfiles = true);

    try {
      int createdCount = 0;
      int linkedCount = 0;
      final db = FirebaseFirestore.instance;

      for (final entityName in _selectedEntities) {
        String? uid;

        // 1. Check if profile already exists
        final handle = entityName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');

        DocumentSnapshot? userDoc;
        try {
          userDoc = await db.collection('usernames').doc(handle).get();
        } catch (e) {
          print("Error checking username $handle: $e");
        }

        if (userDoc != null && userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>?;
          if (data != null) {
            if (data['redirect'] != null) {
              final target = data['redirect'];
              final targetDoc = await db.collection('usernames').doc(target).get();
              uid = targetDoc.data()?['uid'];
            } else {
              uid = data['uid'];
            }
          }
        } else {
          // Create New Profile
          final parts = entityName.split(' ');
          final first = parts.first;
          final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';

          uid = await createManagedProfile(firstName: first, lastName: last, bio: "Auto-created from Entity Review");
          createdCount++;
        }

        // 2. Publish Relations (Update Fanzines)
        if (uid != null) {
          final fanzineIds = _entityToFanzineIds[entityName] ?? {};
          for (final fid in fanzineIds) {
            await db.collection('fanzines').doc(fid).update({
              'mentionedUsers': FieldValue.arrayUnion(['user:$uid'])
            });
            linkedCount++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Profiles: Created $createdCount, Found/Linked ${linkedCount}. Updated $linkedCount fanzine links."))
        );
        setState(() {
          _selectedEntities.clear();
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isCreatingProfiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    if (!userProvider.isLoading && !userProvider.isEditor) {
      return const Scaffold(body: Center(child: Text("Access Denied: Curators Only.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Curator Dashboard'),
        backgroundColor: Colors.white,
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          tabs: const [
            Tab(text: "Fanzine Review", icon: Icon(Icons.rate_review)),
            Tab(text: "Entity Review", icon: Icon(Icons.people_alt)),
          ],
        ),
      ),
      backgroundColor: Colors.grey[100],
      body: PageWrapper(
        maxWidth: 1200,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildFanzineReviewTab(),
            _buildEntityReviewTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildFanzineReviewTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text("Draft Fanzines", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('fanzines')
                .where('status', isEqualTo: 'draft')
                .orderBy('creationDate', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final errorMsg = snapshot.error.toString();
                final urlRegex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
                final match = urlRegex.firstMatch(errorMsg);
                final indexUrl = match?.group(0);

                return Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(16),
                    constraints: const BoxConstraints(maxWidth: 600),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.build_circle, color: Colors.red, size: 40),
                        const SizedBox(height: 8),
                        const Text("Database Setup Required", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        const SizedBox(height: 8),
                        SelectableText("Firestore requires an index.\n$errorMsg", textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        if (indexUrl != null)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.open_in_new),
                            label: const Text("Create Index Now"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            onPressed: () => launchUrl(Uri.parse(indexUrl)),
                          ),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                      SizedBox(height: 16),
                      Text("No drafts found."),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (c, i) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final id = docs[index].id;
                  final title = data['title'] ?? 'Untitled Fanzine';
                  final date = (data['creationDate'] as Timestamp?)?.toDate();
                  final dateStr = date != null ? DateFormat.yMMMd().format(date) : 'New';
                  final status = data['processingStatus'] ?? 'idle';
                  final errorLog = data['errorLog'];

                  final isProcessing = status == 'processing' || status == 'processing_images';
                  final isError = status == 'error';

                  return Card(
                    child: ListTile(
                      leading: isProcessing
                          ? const SizedBox(width: 40, child: Center(child: CircularProgressIndicator()))
                          : isError
                          ? const Icon(Icons.error, size: 40, color: Colors.red)
                          : const Icon(Icons.book, size: 40, color: Colors.indigo),
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      // CHANGED: Show error status specifically
                      subtitle: isProcessing
                          ? const Text("Processing...", style: TextStyle(color: Colors.orange))
                          : isError
                          ? Text("Error: ${errorLog ?? 'Unknown error'}", style: const TextStyle(color: Colors.red))
                          : Text("Created: $dateStr"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.blue),
                            tooltip: "Rescan",
                            onPressed: isProcessing ? null : () => _rescanFanzine(context, id),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text("Workbench"),
                            onPressed: () => context.push('/workbench/$id'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: "Delete",
                            onPressed: isProcessing ? null : () => _deleteFanzine(context, id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEntityReviewTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fanzines')
          .where('status', isEqualTo: 'draft')
          .snapshots(),
      builder: (context, fanzineSnap) {
        if (!fanzineSnap.hasData) return const Center(child: CircularProgressIndicator());

        final fanzineDocs = fanzineSnap.data!.docs;
        if (fanzineDocs.isEmpty) return const Center(child: Text("No drafts to review."));

        return FutureBuilder<List<Map<String, dynamic>>>(
          // Use the fanzine docs to build the entity list
          future: _aggregateEntities(fanzineDocs),
          builder: (context, entitySnap) {
            if (entitySnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (entitySnap.hasError) {
              return Center(child: SelectableText("Error loading entities: ${entitySnap.error}"));
            }

            final entities = entitySnap.data ?? [];
            if (entities.isEmpty) return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "No entities found yet. \n\nClick 'Rescan' on your draft fanzines to populate this list.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Text("Found ${entities.length} entities", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _isCreatingProfiles || _selectedEntities.isEmpty ? null : _createSelectedProfiles,
                        icon: const Icon(Icons.person_add),
                        label: Text(_isCreatingProfiles ? "Working..." : "Create / Link (${_selectedEntities.length})"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: entities.length,
                    separatorBuilder: (c, i) => const Divider(),
                    itemBuilder: (context, index) {
                      final entity = entities[index];
                      final name = entity['name'];
                      final count = entity['count'];
                      final existingHandle = entity['existingHandle'];
                      final isChecked = _selectedEntities.contains(name);

                      return CheckboxListTile(
                        value: isChecked,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedEntities.add(name);
                            } else {
                              _selectedEntities.remove(name);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
                            if (existingHandle != null) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => context.push('/$existingHandle'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.link, size: 12, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Text(
                                        "/$existingHandle",
                                        style: const TextStyle(
                                          color: Colors.blue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text("Found in $count draft fanzines"),
                        secondary: const Icon(Icons.person_outline),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _aggregateEntities(List<QueryDocumentSnapshot> fanzineDocs) async {
    final Map<String, int> entityCounts = {};
    _entityToFanzineIds.clear();
    final db = FirebaseFirestore.instance;

    // NEW OPTIMIZED APPROACH:
    // Read directly from Fanzine document 'draftEntities' field.
    // Zero page reads required.

    for (final doc in fanzineDocs) {
      final fanzineId = doc.id;
      final data = doc.data() as Map<String, dynamic>;

      // Get the aggregated list from the fanzine doc (populated by main.py)
      final entities = List<String>.from(data['draftEntities'] ?? []);

      for (final entity in entities) {
        entityCounts[entity] = (entityCounts[entity] ?? 0) + 1;

        if (!_entityToFanzineIds.containsKey(entity)) {
          _entityToFanzineIds[entity] = {};
        }
        _entityToFanzineIds[entity]!.add(fanzineId);
      }
    }

    // Check for existence of handles
    final List<Map<String, dynamic>> result = [];
    final List<Future<void>> lookupFutures = [];

    // Sort so most frequent are processed first
    final sortedEntries = entityCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Check top 50 to avoid hammering Firestore
    for (final entry in sortedEntries.take(50)) {
      lookupFutures.add(() async {
        final name = entry.key;
        final count = entry.value;
        String? existingHandle;

        String handle = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');

        if (handle.isNotEmpty) {
          if (name.contains(' ') && !handle.contains('-')) {
            handle = name.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
          }

          try {
            final userDoc = await db.collection('usernames').doc(handle).get();
            if (userDoc.exists) {
              existingHandle = handle;
            }
          } catch (e) {
            // Ignore read errors
          }
        }

        result.add({
          'name': name,
          'count': count,
          'existingHandle': existingHandle,
        });
      }());
    }

    await Future.wait(lookupFutures);
    result.sort((a, b) => b['count'].compareTo(a['count']));
    return result;
  }
}