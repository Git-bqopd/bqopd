import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// The editor settings widget for Calendar "Folios".
/// Sits in the sidebar drawer or "Settings" tab of the Fanzine View Editor.
class CalendarEditorWidget extends StatefulWidget {
  final String folioId; // The ID of the calendar fanzine/folio

  const CalendarEditorWidget({super.key, required this.folioId});

  @override
  State<CalendarEditorWidget> createState() => _CalendarEditorWidgetState();
}

class _CalendarEditorWidgetState extends State<CalendarEditorWidget> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _titleController = TextEditingController();

  final _nameCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  String _selectedMonth = 'February';
  String _selectedDay = '13';
  bool _isHighlighted = false;
  bool _bqopdAttending = false;

  // Folio Settings
  int _startMonth = 2; // Default February
  int _startYear = 2026;

  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _loadFolioData();
  }

  Future<void> _loadFolioData() async {
    final doc = await _db.collection('fanzines').doc(widget.folioId).get();
    if (doc.exists && mounted) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _titleController.text = data['title'] ?? '';
        _startMonth = data['startMonth'] ?? 2;
        _startYear = data['startYear'] ?? 2026;
      });
    }
  }

  Future<void> _updateSettings() async {
    await _db.collection('fanzines').doc(widget.folioId).update({
      'title': _titleController.text.trim(),
      'startMonth': _startMonth,
      'startYear': _startYear,
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Folio Settings Updated")));
  }

  Future<void> _addEvent() async {
    if (_nameCtrl.text.isEmpty) return;
    await _db.collection('conventions').add({
      'name': _nameCtrl.text.trim(),
      'handle': _handleCtrl.text.trim(),
      'location': _locationCtrl.text.trim(),
      'month': _selectedMonth,
      'startDay': _selectedDay,
      'isHighlighted': _isHighlighted,
      'bqopdAttending': _bqopdAttending,
      'folioId': widget.folioId,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _nameCtrl.clear();
    _handleCtrl.clear();
    _locationCtrl.clear();
    setState(() { _isHighlighted = false; _bqopdAttending = false; });
  }

  Future<void> _deleteEvent(String id) async {
    await _db.collection('conventions').doc(id).delete();
  }

  Future<void> _toggleSpread(String pageId, bool val) async {
    await _db.collection('fanzines').doc(widget.folioId).collection('pages').doc(pageId).update({
      'isSpread': val,
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.black,
            indicatorColor: Colors.black,
            labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: "Settings", icon: Icon(Icons.settings, size: 18)),
              Tab(text: "Database", icon: Icon(Icons.calendar_month, size: 18)),
              Tab(text: "Pages", icon: Icon(Icons.auto_awesome_motion, size: 18)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // --- TAB 1: FOLIO SETTINGS ---
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("FOLIO TITLE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 20),
                      const Text("CALENDAR STARTING POINT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              value: _startMonth,
                              decoration: const InputDecoration(labelText: "Month", border: OutlineInputBorder(), isDense: true),
                              items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(_months[i]))),
                              onChanged: (v) => setState(() => _startMonth = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _startYear,
                              decoration: const InputDecoration(labelText: "Year", border: OutlineInputBorder(), isDense: true),
                              items: [2025, 2026, 2027, 2028].map((y) => DropdownMenuItem(value: y, child: Text("$y"))).toList(),
                              onChanged: (v) => setState(() => _startYear = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _updateSettings, child: const Text("Save Folio Configuration")),
                    ],
                  ),
                ),

                // --- TAB 2: CONVENTION MANAGER ---
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("ADD CONVENTION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedMonth,
                        items: _months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                        onChanged: (v) => setState(() => _selectedMonth = v!),
                        decoration: const InputDecoration(labelText: 'Match Month Name', border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 8),
                      TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Convention Name', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextField(controller: _handleCtrl, decoration: const InputDecoration(labelText: '@handle', border: OutlineInputBorder(), isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: _locationCtrl, decoration: const InputDecoration(labelText: 'City, ST', border: OutlineInputBorder(), isDense: true))),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(labelText: 'Match Start Day (e.g. 19)', border: OutlineInputBorder(), isDense: true),
                        onChanged: (v) => _selectedDay = v,
                      ),
                      CheckboxListTile(
                        title: const Text("Highlight Box", style: TextStyle(fontSize: 12)),
                        value: _isHighlighted,
                        onChanged: (v) => setState(() => _isHighlighted = v ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        title: const Text("BQOPD Banner", style: TextStyle(fontSize: 12)),
                        value: _bqopdAttending,
                        onChanged: (v) => setState(() => _bqopdAttending = v ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      ElevatedButton(onPressed: _addEvent, child: const Text("Commit to Database")),
                      const Divider(height: 32),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                            stream: _db.collection('conventions')
                                .where('folioId', isEqualTo: widget.folioId)
                                .orderBy('timestamp', descending: true)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                              final docs = snapshot.data!.docs;
                              if (docs.isEmpty) return const Center(child: Text("No conventions added.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)));

                              return ListView.separated(
                                itemCount: docs.length,
                                separatorBuilder: (c, i) => const Divider(height: 1),
                                itemBuilder: (c, i) {
                                  final data = docs[i].data() as Map<String, dynamic>;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: Text("${data['name']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text("${data['month']} ${data['startDay']}"),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                      onPressed: () => _deleteEvent(docs[i].id),
                                    ),
                                  );
                                },
                              );
                            }
                        ),
                      ),
                    ],
                  ),
                ),

                // --- TAB 3: PAGES & SPREADS ---
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("FOLIO PAGES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 12),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                            stream: _db.collection('fanzines').doc(widget.folioId).collection('pages').orderBy('pageNumber').snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                              final docs = snapshot.data!.docs;
                              return ListView.separated(
                                itemCount: docs.length,
                                separatorBuilder: (c, i) => const Divider(height: 1),
                                itemBuilder: (c, i) {
                                  final data = docs[i].data() as Map<String, dynamic>;
                                  final int num = data['pageNumber'] ?? 0;
                                  final bool isSpread = data['isSpread'] ?? false;

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(radius: 12, backgroundColor: Colors.black, child: Text("$num", style: const TextStyle(color: Colors.white, fontSize: 10))),
                                    title: const Text("Two Page Spread", style: TextStyle(fontSize: 13)),
                                    trailing: Switch(
                                      value: isSpread,
                                      onChanged: (v) => _toggleSpread(docs[i].id, v),
                                    ),
                                  );
                                },
                              );
                            }
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
  }
}