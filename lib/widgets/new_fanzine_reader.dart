import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/view_service.dart';
import '../utils/new_fanzine_single_view.dart';

class NewFanzineReader extends StatefulWidget {
  final String fanzineId;
  final Widget? headerWidget; // Optional header (like the cover/indicia)

  const NewFanzineReader({
    super.key,
    required this.fanzineId,
    this.headerWidget,
  });

  @override
  State<NewFanzineReader> createState() => _NewFanzineReaderState();
}

class _NewFanzineReaderState extends State<NewFanzineReader> {
  final ViewService _viewService = ViewService();
  List<Map<String, dynamic>> _pages = [];
  bool _isLoading = true;
  String? _error;
  String? _resolvedDocId; // Added to store the actual Firestore ID

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    if (widget.fanzineId.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = "Invalid ID"; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    String realDocId = widget.fanzineId;

    try {
      // 1. RESOLVE ID: Check if the input is a ShortCode (e.g., Z1766365778)
      final shortcodeSnap = await FirebaseFirestore.instance
          .collection('shortcodes')
          .doc(widget.fanzineId.toUpperCase())
          .get();

      if (shortcodeSnap.exists) {
        final data = shortcodeSnap.data();
        if (data != null && data['type'] == 'fanzine') {
          realDocId = data['contentId'];
        }
      }

      // 2. Fetch Pages using the resolved Doc ID
      final snapshot = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(realDocId)
          .collection('pages')
          .get();

      final docs = snapshot.docs.map((d) {
        final data = d.data();
        data['__id'] = d.id; // Ensure page ID is available for engagement
        return data;
      }).toList();

      // Sort by pageNumber
      docs.sort((a, b) {
        int aNum = (a['pageNumber'] ?? a['index'] ?? 0) as int;
        int bNum = (b['pageNumber'] ?? b['index'] ?? 0) as int;
        return aNum.compareTo(bNum);
      });

      if (mounted) {
        setState(() {
          _resolvedDocId = realDocId;
          _pages = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading new fanzine reader: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text("Error: $_error"));
    }

    if (_pages.isEmpty || _resolvedDocId == null) {
      return const Center(child: Text("This fanzine has no pages yet."));
    }

    return NewFanzineSingleView(
      fanzineId: _resolvedDocId!, // Passed the resolved ID to fix the missing argument error
      pages: _pages,
      headerWidget: widget.headerWidget ?? const SizedBox.shrink(),
      viewService: _viewService,
    );
  }
}