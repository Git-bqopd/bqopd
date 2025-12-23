import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/user_provider.dart';

class CuratorDashboardPage extends StatefulWidget {
  const CuratorDashboardPage({super.key});

  @override
  State<CuratorDashboardPage> createState() => _CuratorDashboardPageState();
}

class _CuratorDashboardPageState extends State<CuratorDashboardPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
          PageWrapper(maxWidth: 1400, child: _buildDraftsList()),
          const Center(child: Text("Entity Review Hub coming soon")),
        ],
      ),
    );
  }

  Widget _buildDraftsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fanzines')
          .where('status', isEqualTo: 'draft')
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
              DataColumn(label: Text('Page Creation Errors', style: TextStyle(color: Colors.red))),
              DataColumn(label: Text('OCR Errors', style: TextStyle(color: Colors.red))),
              DataColumn(label: Text('Entity ID Errors', style: TextStyle(color: Colors.red))),
              DataColumn(label: Text('Aggregation Errors', style: TextStyle(color: Colors.red))),
              DataColumn(label: Text('Rescan')),
              DataColumn(label: Text('Workbench')),
              DataColumn(label: Text('Delete')),
            ],
            rows: docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final id = doc.id;

              return DataRow(cells: [
                DataCell(
                    SizedBox(
                      width: 180,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['title'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          Text(data['processingStatus'] ?? 'idle', style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
                        ],
                      ),
                    )
                ),
                DataCell(_ErrorCounter(fanzineId: id, type: 'ingest', parentValue: data['error_ingest'])),
                DataCell(_ErrorCounter(fanzineId: id, type: 'ocr')),
                DataCell(_ErrorCounter(fanzineId: id, type: 'entity')),
                DataCell(_ErrorCounter(fanzineId: id, type: 'agg', parentValue: data['error_agg'])),
                DataCell(
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                      onPressed: () => _rescanFanzine(id),
                    )
                ),
                DataCell(
                    ElevatedButton(
                      onPressed: () => context.push('/workbench/$id'),
                      child: const Text("Workbench"),
                    )
                ),
                DataCell(
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteFanzine(id),
                    )
                ),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }
}

class _ErrorCounter extends StatelessWidget {
  final String fanzineId;
  final String type;
  final dynamic parentValue;

  const _ErrorCounter({required this.fanzineId, required this.type, this.parentValue});

  @override
  Widget build(BuildContext context) {
    if (type == 'ingest' || type == 'agg') {
      int val = 0;
      if (parentValue is int) val = parentValue;
      else if (parentValue != null && parentValue != 0) val = 1;
      return Center(
        child: Text(
            val.toString(),
            style: TextStyle(
                color: val > 0 ? Colors.red : Colors.grey.shade400,
                fontWeight: val > 0 ? FontWeight.bold : FontWeight.normal
            )
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('fanzines').doc(fanzineId).collection('pages').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: Text("0", style: TextStyle(color: Colors.grey)));

        int count = 0;
        for (var doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          if (type == 'ocr' && (d['status'] == 'error' || (d['error_ocr'] ?? 0) > 0)) {
            count++;
          }
          if (type == 'entity' && (d['error_entity_id'] ?? 0) > 0) {
            count++;
          }
        }

        return Center(
          child: Text(
              count.toString(),
              style: TextStyle(
                  color: count > 0 ? Colors.red : Colors.grey.shade400,
                  fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal
              )
          ),
        );
      },
    );
  }
}