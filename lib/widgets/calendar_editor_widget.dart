import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/con_week.dart';
import '../models/page_event.dart';

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

  // Phase 1: Week Selection State
  List<ConWeek> _availableWeeks = [];
  ConWeek? _selectedWeek;

  // Phase 2 & 3: Selection State
  PageEvent? _selectedEvent;

  // Toggles
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
        _initializeWeeks();
      });
    }
  }

  void _initializeWeeks() {
    final startMonthStr = _months[_startMonth - 1];
    final startYearStr = _startYear.toString();

    setState(() {
      _availableWeeks = generateConWeeks(startMonthStr, startYearStr);
      if (_availableWeeks.isNotEmpty) {
        _selectedWeek = _availableWeeks.first;
      }
    });
  }

  Future<void> _updateSettings() async {
    await _db.collection('fanzines').doc(widget.folioId).update({
      'title': _titleController.text.trim(),
      'startMonth': _startMonth,
      'startYear': _startYear,
    });

    // Refresh weeks if the start date changed
    _initializeWeeks();

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Folio Settings Updated")));
  }

  /// Phase 4: Save Mapping
  /// Maps the selected PageEvent and ConWeek into the 'conventions' collection format.
  Future<void> _addEvent() async {
    if (_selectedEvent == null || _selectedWeek == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a week and an event card first.")));
      return;
    }

    // Determine the month name from the selected Thursday (the week's start)
    final monthName = _months[_selectedWeek!.startDate.month - 1];
    final startDay = _selectedWeek!.startDate.day.toString();

    // Map community PageEvent fields to the internal Convention schema
    await _db.collection('conventions').add({
      'name': _selectedEvent!.eventName,
      'handle': '@${_selectedEvent!.username}',
      'location': '${_selectedEvent!.city}, ${_selectedEvent!.state}',
      'month': monthName,
      'startDay': startDay,
      'isHighlighted': _isHighlighted,
      'bqopdAttending': _bqopdAttending,
      'folioId': widget.folioId,
      'timestamp': FieldValue.serverTimestamp(),
      'originalEventId': _selectedEvent!.id, // Reference to original community event
    });

    if (mounted) {
      setState(() {
        // Reset selection state after committing
        _selectedEvent = null;
        _isHighlighted = false;
        _bqopdAttending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Convention added to Folio!")));
    }
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
                      const Text("SELECT WEEK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<ConWeek>(
                        decoration: const InputDecoration(
                            labelText: 'Convention Week (Thu-Sun)',
                            border: OutlineInputBorder(),
                            isDense: true
                        ),
                        value: _selectedWeek,
                        items: _availableWeeks.map((week) {
                          return DropdownMenuItem<ConWeek>(
                            value: week,
                            child: Text(week.displayString, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (ConWeek? newValue) {
                          setState(() {
                            _selectedWeek = newValue;
                            _selectedEvent = null; // Reset selection on week change
                          });
                        },
                      ),

                      const SizedBox(height: 16),
                      const Text("CONVENTIONS THIS WEEK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
                      const SizedBox(height: 8),

                      // Database Search Results
                      SizedBox(
                        height: 160,
                        child: _selectedWeek == null
                            ? const Center(child: Text("Select a week to search", style: TextStyle(fontSize: 11, color: Colors.grey)))
                            : StreamBuilder<QuerySnapshot>(
                          stream: _db.collection('page_events')
                              .where('startDate', isGreaterThanOrEqualTo: Timestamp.fromDate(_selectedWeek!.startDate))
                              .where('startDate', isLessThanOrEqualTo: Timestamp.fromDate(_selectedWeek!.endDate))
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 10)));
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                            final docs = snapshot.data!.docs;
                            if (docs.isEmpty) return const Center(child: Text("No events found in database.", style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)));

                            return ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                final data = doc.data() as Map<String, dynamic>;
                                final event = PageEvent.fromMap(data, doc.id);
                                final bool isSelected = _selectedEvent?.id == event.id;

                                return GestureDetector(
                                  onTap: () => setState(() => _selectedEvent = event),
                                  child: Container(
                                    width: 140,
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.black : Colors.white,
                                      border: Border.all(color: isSelected ? Colors.black : Colors.grey[300]!),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          event.eventName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: isSelected ? Colors.white : Colors.black
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          "${event.city}, ${event.state}",
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: isSelected ? Colors.grey[400] : Colors.grey[600]
                                          ),
                                        ),
                                        Text(
                                          "@${event.username}",
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected ? Colors.amber : Colors.blue
                                          ),
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

                      const SizedBox(height: 8),
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
                      ElevatedButton(
                          onPressed: _selectedEvent == null ? null : _addEvent,
                          child: const Text("Commit to Database")
                      ),
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