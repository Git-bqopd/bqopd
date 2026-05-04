import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../calendar_editor_widget.dart';
import '../templates/basic_text_template.dart';

class PublisherPanel extends StatelessWidget {
  final String imageId;
  final String initialText;
  final String fanzineId;
  final String? templateId;

  const PublisherPanel({
    super.key,
    required this.imageId,
    required this.initialText,
    required this.fanzineId,
    this.templateId,
  });

  @override
  Widget build(BuildContext context) {
    if (templateId != null && templateId!.startsWith('calendar')) {
      return CalendarEditorWidget(folioId: fanzineId);
    }
    return InlineTextEditor(
      imageId: imageId,
      initialText: initialText,
      showPublisherPreview: true,
    );
  }
}

class InlineTextEditor extends StatefulWidget {
  final String imageId;
  final String initialText;
  final bool showPublisherPreview;

  const InlineTextEditor({
    super.key,
    required this.imageId,
    required this.initialText,
    this.showPublisherPreview = false,
  });

  @override
  State<InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<InlineTextEditor> {
  late TextEditingController _c;
  bool _s = false;
  bool _p = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialText);
    _p = widget.showPublisherPreview;
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
      await FirebaseFirestore.instance.collection('images').doc(widget.imageId).update({
        'text_corrected': _c.text,
        'needs_linking': true,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved Gold Master!')));
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
            Text(
              widget.showPublisherPreview ? "CHICKEN EDITOR (PUBLISHER)" : "TEXT EDITOR",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_p ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _p = !_p),
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _s ? null : _save,
                ),
              ],
            )
          ],
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