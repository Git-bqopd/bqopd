import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/user_provider.dart';

class CuratorDashboardPage extends StatelessWidget {
  const CuratorDashboardPage({super.key});

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

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Starting Rescan...")));

    try {
      await FirebaseFunctions.instance.httpsCallable('rescan_fanzine').call({
        'fanzineId': fanzineId,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rescan Complete!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
      ),
      backgroundColor: Colors.grey[100],
      body: PageWrapper(
        maxWidth: 1200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Draft Fanzines (Review Needed)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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

                      final isProcessing = status == 'processing' || status == 'processing_images';

                      return Card(
                        child: ListTile(
                          leading: isProcessing
                              ? const SizedBox(width: 40, child: Center(child: CircularProgressIndicator()))
                              : const Icon(Icons.book, size: 40, color: Colors.indigo),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(isProcessing ? "Processing..." : "Created: $dateStr"),
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
        ),
      ),
    );
  }
}