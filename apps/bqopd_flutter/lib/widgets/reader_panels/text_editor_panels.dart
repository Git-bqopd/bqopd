import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

// --- MASTER TEXT PANEL ---
class MasterTextPanel extends StatelessWidget {
  final String imageId;
  final String initialText;
  final String aiBaselineText;
  final String fanzineId;
  final String? templateId;

  const MasterTextPanel({
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
      mode: 'master',
      fanzineId: fanzineId,
    );
  }
}

// --- LINKED TEXT PANEL ---
class LinkedTextPanel extends StatelessWidget {
  final String imageId;
  final String initialText;
  final String aiBaselineText;
  final String fanzineId; // Added to enable bubbling up of manual entities

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
      mode: 'linked',
      fanzineId: fanzineId,
    );
  }
}

// --- SHARED EDITOR LOGIC ---
class _InlineTextEditor extends StatefulWidget {
  final String imageId;
  final String initialText;
  final String aiBaselineText;
  final String mode; // 'master' or 'linked'
  final String fanzineId; // Passed down to update Fanzine metadata

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

  Future<void> _save() async {
    if (widget.imageId.isEmpty) return;
    setState(() => _s = true);

    try {
      final Map<String, dynamic> updates = {};

      if (widget.mode == 'master') {
        updates['text_corrected'] = _c.text;
        updates['needs_linking'] = true;
      } else {
        updates['text_linked'] = _c.text;

        // Parse manual [[Entity]] brackets and instantly bubble them up to the Fanzine!
        final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
        final matches = regex.allMatches(_c.text);
        final List<String> manualEntities = [];

        for (final m in matches) {
          final name = m.group(1);
          if (name != null && name.isNotEmpty) manualEntities.add(name);
        }

        updates['detected_entities'] = manualEntities;

        if (widget.fanzineId.isNotEmpty && manualEntities.isNotEmpty) {
          FirebaseFirestore.instance.collection('fanzines').doc(widget.fanzineId).update({
            'draftEntities': FieldValue.arrayUnion(manualEntities)
          });
        }
      }

      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update(updates);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error saving: $e'),
        backgroundColor: Colors.red,
      ));
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

    final bool isMaster = widget.mode == 'master';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isMaster ? "CORRECTED TEXT EDITOR" : "WIKI-LINK EDITOR",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            Row(
              children: [
                if (isMaster)
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
        if (!isMaster)
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text("Use [[Exact Name]] to manually create entity links.", style: TextStyle(fontSize: 10, color: Colors.grey)),
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
        if (_p && isMaster) ...[
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