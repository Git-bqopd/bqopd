import 'dart:math' as Math; // For Math.min in _FanzineListItem
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Import FanzineReaderPage for navigation
import '../pages/fanzine_reader_page.dart'; // Adjust path if needed

class ProfileWidget extends StatefulWidget {
  final String userId;
  final String username; // Username is passed directly

  const ProfileWidget({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> {
  Stream<QuerySnapshot>? _userFanzinesStream;

  @override
  void initState() {
    super.initState();
    _initFanzinesStream();
  }

  void _initFanzinesStream() {
    _userFanzinesStream = FirebaseFirestore.instance
        .collection('fanzines')
        .where('authorID', isEqualTo: widget.userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
    print("Fanzine stream initialized for user ID: \${widget.userId}");
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1B255),
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    Text(
                      widget.username,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4.0),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/my_info_page'),
                      child: const Text(
                        'my info',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.black54),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  "\${widget.username}'s Fanzines",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _userFanzinesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.black54));
                    }
                    if (snapshot.hasError) {
                      print("Error in StreamBuilder for user \${widget.userId}: \${snapshot.error}");
                      return Center(child: Text('Error loading fanzines: \${snapshot.error}', style: const TextStyle(color: Colors.red)));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text("No fanzines found for this user.", style: TextStyle(color: Colors.black54)));
                    }

                    final fanzines = snapshot.data!.docs;

                    return GridView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8.0,
                        mainAxisSpacing: 8.0,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: fanzines.length,
                      itemBuilder: (context, index) {
                        return _FanzineListItem(fanzineDoc: fanzines[index]);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FanzineListItem extends StatelessWidget {
  final QueryDocumentSnapshot fanzineDoc;

  const _FanzineListItem({required this.fanzineDoc});

  @override
  Widget build(BuildContext context) {
    final data = fanzineDoc.data() as Map<String, dynamic>;
    final String title = data['title'] ?? 'Untitled Fanzine';
    final String? coverImageURL = data['coverImageURL'];
    final String fanzineId = fanzineDoc.id;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FanzineReaderPage(
              fanzineID: fanzineId,
              fanzineTitle: title,
            ),
          ),
        );
      },
      child: Card(
        elevation: 3.0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: (coverImageURL != null && coverImageURL.isNotEmpty)
                  ? Image.network(
                coverImageURL,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: Center(child: Icon(Icons.broken_image_rounded, color: Colors.grey[600], size: 40)),
                  );
                },
              )
                  : Container(
                color: Colors.grey[300],
                child: Center(child: Icon(Icons.collections_bookmark_rounded, color: Colors.grey[600], size: 40)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}