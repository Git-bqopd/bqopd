import 'package:bqopd/components/social_toolbar.dart';
import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/templates/basic_text_template.dart';

class PublisherPage extends StatefulWidget {
  const PublisherPage({super.key});

  @override
  State<PublisherPage> createState() => _PublisherPageState();
}

class _PublisherPageState extends State<PublisherPage> {
  late TextEditingController _textController;
  bool _isTextDrawerOpen = true;
  bool _isSaving = false;

  final String _initialText = """
# THE COMET
## Issue #1 - January 2026

Welcome to the first issue of The Comet. This is a generated page proving that we can take raw text and turn it into a beautiful, printable artifact.

{{IMAGE}}

### CAST OF CHARACTERS

* **Kevin:** The Curator
* **Gemini:** The Ghost in the Machine
* **You:** The Reader

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
      await FirebaseFirestore.instance.collection('images').add({
        'uploaderId': user.uid,
        'type': 'text_template',
        'templateId': 'basic_text_3col',
        'text': _textController.text,
        'title': 'Generated Page',
        'timestamp': FieldValue.serverTimestamp(),
        'fileUrl': 'https://placehold.co/400x600/png?text=Text+Page',
        'isGenerated': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Page saved to your profile!")),
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
    return Scaffold(
      backgroundColor: Colors.grey[800],
      appBar: AppBar(
        title: const Text("Publisher Workbench"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            ))
          else
            TextButton.icon(
              onPressed: _savePage,
              icon: const Icon(Icons.save, color: Colors.green),
              label: const Text("SAVE PAGE", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
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
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16.0),
                          child: Text(
                            "Live Preview (2000 x 3200)",
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: _textController,
                            builder: (context, _) {
                              // Use the correct pagination method: paginateContent
                              final pagesOfBlocks = BasicTextTemplate.paginateContent(_textController.text);

                              return ListView.separated(
                                itemCount: pagesOfBlocks.length,
                                separatorBuilder: (c, i) => const SizedBox(height: 40),
                                itemBuilder: (context, index) {
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SocialToolbar(
                    pageId: 'publisher_preview',
                    fanzineId: 'publisher_preview',
                    onToggleText: _toggleTextDrawer,
                  ),
                ),
              ],
            ),
          ),
          if (_isTextDrawerOpen)
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
                        const Text("TEXT EDITOR", style: TextStyle(fontWeight: FontWeight.bold)),
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
                          hintText: "Enter your text here. Use {{IMAGE}} to insert.",
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontFamily: 'Courier', fontSize: 14),
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
}