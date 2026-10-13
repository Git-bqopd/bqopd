import 'package:bqopd_core/bqopd_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../components/dynamic_social_toolbar.dart';
import '../widgets/page_wrapper.dart';
import '../widgets/templates/basic_text_template.dart';
import '../widgets/templates/calendar_template.dart';

/// Interactive Publisher Workbench for drafting and previewing registered page templates.
/// Dynamically queries [PageTemplateRegistry] for all available layout options.
class PublisherPage extends StatefulWidget {
  const PublisherPage({super.key});

  @override
  State<PublisherPage> createState() => _PublisherPageState();
}

class _PublisherPageState extends State<PublisherPage> {
  late TextEditingController _textController;
  bool _isTextDrawerOpen = true;
  bool _isSaving = false;

  // Template Selection State sourced dynamically from PageTemplateRegistry
  String _selectedTemplate = 'basic_text';

  final String _initialText = """
# THE COMET
## Issue #1 - January 2026

Welcome to the first issue of The Comet. This is a generated page proving that we can take raw text and turn it into a beautiful, printable artifact.

{{IMAGE}}

### CAST OF CHARACTERS

- **Kevin:** The Curator

- **Gemini:** The Ghost in the Machine

- **You:** The Reader


This system uses a 2000x3200 pixel canvas to match the physical dimensions of the printed zine. 

{{IMAGE: https://placehold.co/600x400/png}}

The text you are reading right now is rendered using a standard Flutter widget tree, but constrained to the exact aspect ratio of our final output.

If you can read this, the system is working.
""";

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: _initialText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _toggleTextDrawer() {
    setState(() {
      _isTextDrawerOpen = !_isTextDrawerOpen;
    });
  }

  Future<void> _savePage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be logged in to save.")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final templateDef = PageTemplateRegistry.getTemplate(_selectedTemplate);
      final int templateWidth = templateDef?.width ?? 2000;
      final int templateHeight = templateDef?.height ?? 3200;
      final double templateAspectRatio = templateDef?.aspectRatio ?? 0.625;
      final String templateTitle = templateDef?.name ?? 'Generated Page';

      await FirebaseFirestore.instance.collection('images').add({
        'uploaderId': user.uid,
        'type': 'template',
        'templateId': _selectedTemplate,
        'text': _selectedTemplate == 'basic_text'
            ? _textController.text
            : '$templateTitle Data',
        'title': templateTitle,
        'timestamp': FieldValue.serverTimestamp(),
        'fileUrl': 'https://placehold.co/400x600/png?text=Generated+Page',
        'isGenerated': true,
        'width': templateWidth,
        'height': templateHeight,
        'aspectRatio': templateAspectRatio,
        'is5x8': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$templateTitle saved to your profile!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allTemplates = PageTemplateRegistry.getAllTemplates();

    return Scaffold(
      backgroundColor: Colors.grey[800],
      appBar: AppBar(
        title: const Text("Publisher Workbench"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // Dynamic Template Selector populated from PageTemplateRegistry
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButton<String>(
              value: _selectedTemplate,
              dropdownColor: Colors.grey[900],
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              items: allTemplates.map((tmpl) {
                return DropdownMenuItem<String>(
                  value: tmpl.id,
                  child: Text(tmpl.name),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedTemplate = val);
              },
            ),
          ),
          const VerticalDivider(
            color: Colors.white24,
            width: 1,
            indent: 12,
            endIndent: 12,
          ),
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _savePage,
              icon: const Icon(Icons.save, color: Colors.green),
              label: const Text(
                "SAVE PAGE",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: PageWrapper(
                    maxWidth: 1200,
                    scroll: false,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Text(
                            _selectedTemplate.startsWith('calendar')
                                ? "Live Preview (4000 x 3200 Spread)"
                                : "Live Preview (2000 x 3200 - ${PageTemplateRegistry.getTemplate(_selectedTemplate)?.name ?? _selectedTemplate})",
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        Expanded(
                          child: _buildPreviewArea(),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: DynamicSocialToolbar(
                    imageId: 'publisher_preview',
                    pageId: null,
                    fanzineId: null,
                    fanzineType: 'folio',
                    pageNumber: null,
                    isEditingMode: true,
                    activeBonusRow:
                    _isTextDrawerOpen ? BonusRowType.textReader : null,
                    onToggleBonusRow: (type) {
                      if (type == BonusRowType.textReader) {
                        _toggleTextDrawer();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_isTextDrawerOpen && _selectedTemplate == 'basic_text')
            Container(
              width: 400,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey[100],
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "TEXT EDITOR",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _toggleTextDrawer,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        decoration: const InputDecoration(
                          hintText:
                          "Enter your text here. Use {{IMAGE}} to insert.",
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea() {
    if (_selectedTemplate.startsWith('calendar')) {
      return InteractiveViewer(
        constrained: false,
        minScale: 0.1,
        maxScale: 2.0,
        boundaryMargin: const EdgeInsets.all(400),
        child: CalendarSpreadTemplate(
          leftPageMonths: CalendarDummyData.getLeftPageBase(),
          rightPageMonths: CalendarDummyData.getRightPageBase(),
        ),
      );
    }

    if (_selectedTemplate == 'map_cover') {
      return Center(
        child: AspectRatio(
          aspectRatio: 2000 / 3200,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE5E3DF),
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map, size: 64, color: Colors.black54),
                SizedBox(height: 16),
                Text(
                  "Geospatial Map Cover",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Rendered dynamically from static Google Map coords & pins",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Default: Basic 3-Column Text Template
    return ListenableBuilder(
      listenable: _textController,
      builder: (context, _) {
        final pagesOfBlocks =
        BasicTextTemplate.paginateContent(_textController.text);

        return ListView.separated(
          itemCount: pagesOfBlocks.length,
          separatorBuilder: (c, i) => const SizedBox(height: 40),
          itemBuilder: (context, index) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    "Page ${index + 1}",
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: BasicTextTemplate(
                      columns: pagesOfBlocks[index],
                      showOverlay: true,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}