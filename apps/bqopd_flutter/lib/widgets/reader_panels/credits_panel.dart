import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreditsPanel extends StatefulWidget {
  final String imageId;
  const CreditsPanel({super.key, required this.imageId});

  @override
  State<CreditsPanel> createState() => _CreditsPanelState();
}

class _CreditsPanelState extends State<CreditsPanel> {
  final TextEditingController _sC = TextEditingController();
  final TextEditingController _rC = TextEditingController();
  final TextEditingController _iC = TextEditingController();

  List<Map<String, dynamic>> _creators = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.imageId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('images').doc(widget.imageId).get();
      if (doc.exists && mounted) {
        final d = doc.data() as Map<String, dynamic>;
        setState(() {
          _iC.text = d['indicia'] ?? '';
          _creators = (d['creators'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (widget.imageId.isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({
        'indicia': _iC.text.trim(),
        'creators': _creators
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageId.isEmpty) {
      return const Text("Image not yet registered.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Indicia / Copyright", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          TextField(
              controller: _iC,
              maxLines: 3,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)
          ),
          const SizedBox(height: 16),
          const Text("Creators", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ..._creators.map((c) => ListTile(
              dense: true,
              title: Text("${c['name']} (${c['role']})"),
              trailing: IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () => setState(() => _creators.remove(c))
              )
          )),
          Row(
              children: [
                Expanded(child: TextField(controller: _sC, decoration: const InputDecoration(hintText: "@handle"))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _rC, decoration: const InputDecoration(hintText: "Role"))),
                IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (_sC.text.isNotEmpty) {
                        setState(() => _creators.add({'name': _sC.text, 'role': _rC.text}));
                      }
                      _sC.clear();
                      _rC.clear();
                    }
                )
              ]
          ),
          ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? "Saving..." : "Save Metadata")
          )
        ]
    );
  }
}