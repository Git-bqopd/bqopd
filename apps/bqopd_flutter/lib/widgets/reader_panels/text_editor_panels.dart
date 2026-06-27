import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../calendar_editor_widget.dart';
import '../templates/basic_text_template.dart';

// --- RAW TEXT PANEL ---
class RawTextPanel extends StatelessWidget {
  final String text;
  const RawTextPanel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const Text("No raw OCR text available yet.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
    }
    return SelectableText(
      text,
      style: const TextStyle(fontFamily: 'Courier', fontSize: 13, color: Colors.black87),
    );
  }
}

// --- EDIT TEXT PANEL (COMBINED EDIT TEXT) ---
class EditTextPanel extends StatelessWidget {
  final String imageId;
  final String initialText;
  final String aiBaselineText;
  final String fanzineId;
  final String? templateId;

  const EditTextPanel({
    super.key,
    required this.imageId,
    required this.initialText,
    required this.aiBaselineText,
    required this.fanzineId,
    this.templateId,
  });

  @override
  Widget build(BuildContext context) {
    if (templateId != null && templateId!.startsWith('calendar')) {
      return CalendarEditorWidget(folioId: fanzineId);
    }
    return _InlineTextEditor(
      imageId: imageId,
      initialText: initialText,
      aiBaselineText: aiBaselineText,
      mode: 'edit', // FIXED: Changed from 'master' to 'edit' to enforce uniform naming conventions
      fanzineId: fanzineId,
    );
  }
}

// --- LINKED TEXT PANEL (COMPATIBILITY WRAPPER REDIRECTS TO UNIFIED WORKSPACE) ---
class LinkedTextPanel extends StatelessWidget {
  final String imageId;
  final String initialText;
  final String aiBaselineText;
  final String fanzineId;

  const LinkedTextPanel({
    super.key,
    required this.imageId,
    required this.initialText,
    required this.aiBaselineText,
    required this.fanzineId,
  });

  @override
  Widget build(BuildContext context) {
    return _InlineTextEditor(
      imageId: imageId,
      initialText: initialText,
      aiBaselineText: aiBaselineText,
      mode: 'edit', // FIXED: Changed from 'master' to 'edit' to enforce uniform naming conventions
      fanzineId: fanzineId,
    );
  }
}

// --- SHARED EDITOR LOGIC ---
class _InlineTextEditor extends StatefulWidget {
  final String imageId;
  final String initialText;
  final String aiBaselineText;
  final String mode;
  final String fanzineId;

  const _InlineTextEditor({
    required this.imageId,
    required this.initialText,
    required this.aiBaselineText,
    required this.mode,
    required this.fanzineId,
  });

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late TextEditingController _c;
  bool _s = false;
  bool _p = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialText);
  }

  @override
  void didUpdateWidget(covariant _InlineTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText) {
      if (_c.text == oldWidget.initialText || _c.text.isEmpty) {
        _c.text = widget.initialText;
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int _calculateEditDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);
    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }

  Future<void> _save() async {
    if (widget.imageId.isEmpty) return;
    setState(() => _s = true);
    try {
      final Map<String, dynamic> updates = {};
      int score = _calculateEditDistance(widget.aiBaselineText, _c.text);

      updates['text_corrected'] = _c.text;
      updates['text_linked'] = _c.text; // Keeps fields aligned programmatically
      updates['needs_linking'] = false; // Bypasses the backend AI linking queue completely!

      // Parse manual [[Entity]] bracket annotations programmatically
      final regex = RegExp(r'\[\[(.*?)\]\]');
      final matches = regex.allMatches(_c.text);
      final List<String> manualEntities = [];
      for (final m in matches) {
        final content = m.group(1) ?? '';
        final parts = content.split('|');
        if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
          manualEntities.add(parts[0].trim());
        }
      }
      updates['detected_entities'] = manualEntities;

      if (widget.fanzineId.isNotEmpty && manualEntities.isNotEmpty) {
        FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).update({
          'draftEntities': FieldValue.arrayUnion(manualEntities)
        });
      }

      if (widget.aiBaselineText.isNotEmpty) {
        updates['human_correction_score'] = score;
        if (score > 0) updates['isTrainingData'] = true;
      }

      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update(updates);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved! (Score: $score)')));
    } finally {
      if (mounted) setState(() => _s = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageId.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          "Waiting for OCR Pipeline to register this page before editing is allowed.",
          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "EDIT TEXT & WIKILINKS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_p ? Icons.visibility_off : Icons.visibility),
                  tooltip: "Toggle Preview",
                  onPressed: () => setState(() => _p = !_p),
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: "Save",
                  onPressed: _s ? null : _save,
                ),
              ],
            )
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8.0),
          child: Text("Edit typos and adjust [[Exact Name]] or [[Exact Name|user:uid]] wiki-links directly.", style: TextStyle(fontSize: 10, color: Colors.grey)),
        ),
        TextField(
          controller: _c,
          maxLines: null,
          minLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            fillColor: Colors.white,
            filled: true,
          ),
          style: const TextStyle(fontFamily: 'Courier', fontSize: 14),
        ),
        if (_p) ...[
          const SizedBox(height: 16),
          const Text(
            "LIVE PREVIEW (2000x3200 SCALE)",
            style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 2000 / 3200,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: FittedBox(
                child: BasicTextTemplate(
                  columns: BasicTextTemplate.paginateContent(_c.text)[0],
                ),
              ),
            ),
          ),
        ]
      ],
    );
  }
}