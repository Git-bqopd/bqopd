import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A specialized modal that allows a user to select images from their total library.
/// Returns a List of Map<String, dynamic> containing image metadata.
class FolioImageSelectorModal extends StatefulWidget {
  final String userId;

  const FolioImageSelectorModal({super.key, required this.userId});

  @override
  State<FolioImageSelectorModal> createState() => _FolioImageSelectorModalState();
}

class _FolioImageSelectorModalState extends State<FolioImageSelectorModal> {
  final Set<String> _selectedImageIds = {};
  final List<Map<String, dynamic>> _selectedMetadata = [];

  void _toggleSelection(String id, Map<String, dynamic> data) {
    setState(() {
      if (_selectedImageIds.contains(id)) {
        _selectedImageIds.remove(id);
        _selectedMetadata.removeWhere((m) => m['id'] == id);
      } else {
        _selectedImageIds.add(id);
        _selectedMetadata.add({...data, 'id': id});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Add from Library (${_selectedImageIds.length})",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      if (_selectedImageIds.isNotEmpty)
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, _selectedMetadata),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("ADD SELECTED"),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  )
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('images')
                    .where('uploaderId', isEqualTo: widget.userId)
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text("No uploaded images found in your library."),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.625, // 5:8 aspect ratio
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final url = data['fileUrl'] ?? '';
                      final isSelected = _selectedImageIds.contains(doc.id);

                      return GestureDetector(
                        onTap: () => _toggleSelection(doc.id, data),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? Colors.indigo : Colors.grey.shade300,
                              width: isSelected ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => const Center(
                                      child: Icon(Icons.broken_image)),
                                ),
                              ),
                              if (isSelected)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.indigo,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: const Icon(Icons.check, color: Colors.white, size: 16),
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
          ],
        ),
      ),
    );
  }
}