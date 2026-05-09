import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class IndiciaPanel extends StatefulWidget {
  final String fanzineId;
  final bool isEditingMode;

  const IndiciaPanel({
    super.key,
    required this.fanzineId,
    required this.isEditingMode,
  });

  @override
  State<IndiciaPanel> createState() => _IndiciaPanelState();
}

class _IndiciaPanelState extends State<IndiciaPanel> {
  final TextEditingController _c = TextEditingController();
  List<Map<String, dynamic>> _assembledCreators = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).get();
    if (doc.exists && mounted) {
      setState(() {
        _c.text = doc.data()?['masterIndicia'] ?? '';
        _assembledCreators = (doc.data()?['masterCreators'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).update({
        'masterIndicia': _c.text.trim(),
        'masterCreators': _assembledCreators,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _autoAssemble() async {
    setState(() => _loading = true);
    try {
      final pagesSnap = await FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).collection('pages').orderBy('pageNumber').get();
      List<String> assembledIndicia = [];
      List<Map<String, dynamic>> allCreators = [];
      Set<String> seenCreatorKeys = {};

      for (var p in pagesSnap.docs) {
        final pData = p.data();
        final imageId = pData['imageId'];
        if (imageId != null && imageId.toString().isNotEmpty) {
          final imgDoc = await FirebaseFirestore.instance.collection('images').doc(imageId).get();
          if (imgDoc.exists) {
            final imgData = imgDoc.data() as Map<String, dynamic>;

            final creators = imgData['creators'] as List? ?? [];
            for (var c in creators) {
              final cMap = Map<String, dynamic>.from(c as Map);
              final key = "${cMap['uid']}_${cMap['name']}_${cMap['role']}";
              if (!seenCreatorKeys.contains(key)) {
                seenCreatorKeys.add(key);
                allCreators.add(cMap);
              }
            }

            final imgIndicia = imgData['indicia'] as String?;
            if (imgIndicia != null && imgIndicia.trim().isNotEmpty) {
              assembledIndicia.add(imgIndicia.trim());
            }
          }
        }
      }

      setState(() {
        _c.text = assembledIndicia.join('\n\n').trim();
        _assembledCreators = allCreators;
      });

    } catch (e) {
      debugPrint("Assemble error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (!widget.isEditingMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("ISSUE INDICIA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(_c.text.isEmpty ? "No indicia available for this issue." : _c.text, style: const TextStyle(fontSize: 12, fontFamily: 'Georgia', height: 1.5)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("INDICIA EDITOR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ElevatedButton.icon(
              onPressed: _autoAssemble,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text("Auto-Assemble Meta", style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
            )
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _c,
          maxLines: null,
          minLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Master Indicia text..."),
          style: const TextStyle(fontSize: 12, fontFamily: 'Georgia', height: 1.5),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? "Saving..." : "Save Master Meta"),
          ),
        )
      ],
    );
  }
}