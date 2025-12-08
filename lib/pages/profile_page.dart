import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../widgets/profile_widget.dart';
import '../widgets/new_fanzine_modal.dart';
import '../widgets/image_view_modal.dart';
import 'fanzine_editor_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // 0 = Editor, 1 = Fanzines, 2 = Pages
  int _currentIndex = 0;

  bool _isEditor = false;
  bool _isLoadingCurrentUser = true;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserEditorStatus();
  }

  Future<void> _loadCurrentUserEditorStatus() async {
    setState(() => _isLoadingCurrentUser = true);
    _currentUser = FirebaseAuth.instance.currentUser;

    if (_currentUser != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(_currentUser!.uid)
            .get();

        if (userDoc.exists && mounted) {
          final data = userDoc.data() as Map<String, dynamic>;
          setState(() => _isEditor = (data['Editor'] == true));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading editor status: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoadingCurrentUser = false);
      }
    } else {
      if (mounted) setState(() => _isLoadingCurrentUser = false);
    }
  }

  void _showNewFanzineModal() {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to create a fanzine.')),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewFanzineModal(userId: _currentUser!.uid),
    );
  }

  int _calcCols(double w) => w >= 1200 ? 4 : (w >= 900 ? 3 : 2);

  ButtonStyle get _blueButtonStyle => TextButton.styleFrom(
    backgroundColor: Colors.blueAccent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  ButtonStyle get _greyButtonStyle => TextButton.styleFrom(
    backgroundColor: Colors.grey,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  // --- TAB 0: EDITOR SECTION (My Created Fanzines + Tools) ---
  Widget _buildEditorSection() {
    if (_isLoadingCurrentUser) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_currentUser == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text("User not loaded. Please try again.")),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fanzines')
          .where('editorId', isEqualTo: _currentUser!.uid)
          .orderBy('creationDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Error loading fanzines.')),
          );
        }

        final displayItems = <Widget>[];

        // --- DEBUG INFO TILE ---
        // This will appear as the first item in your grid so you can verify status
        displayItems.add(
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bug_report, color: Colors.amber),
                Text(
                  "Editor: $_isEditor",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "UID: ${_currentUser!.uid.substring(0, 5)}...",
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        );

        // --- ALWAYS SHOW TOOLS (Removed _isEditor check for debugging) ---
        displayItems.addAll([
          TextButton(
            style: _blueButtonStyle,
            onPressed: _showNewFanzineModal,
            child: const Text(
              "make new fanzine",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            style: _greyButtonStyle,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            child: const Text(
              "settings",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ]);

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final fanzineData = doc.data() as Map<String, dynamic>;
            final title = fanzineData['title'] ?? 'Untitled Fanzine';

            displayItems.add(
              TextButton(
                style: _blueButtonStyle,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FanzineEditorPage(fanzineId: doc.id),
                    ),
                  );
                },
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          }
        }

        return LayoutBuilder(
          builder: (context, c) {
            final cols = _calcCols(c.maxWidth);
            final itemCount = displayItems.isEmpty ? 6 : displayItems.length.clamp(6, 9999);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 5 / 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index < displayItems.length) return displayItems[index];
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- TAB 1: FANZINES SECTION (Consumed Content / Placeholders) ---
  Widget _buildFanzinesSection() {
    final displayItems = <Widget>[
      TextButton(
        style: _blueButtonStyle,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Opening "For You Zine Issue 3"... (Placeholder)')),
          );
        },
        child: const Text(
          "For You Zine Issue 3",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = _calcCols(c.maxWidth);
        final itemCount = 6;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 5 / 8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index < displayItems.length) return displayItems[index];
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            );
          },
        );
      },
    );
  }

  // --- TAB 2: PAGES SECTION (My Images) ---
  Widget _buildPagesSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('images')
          .where('uploaderId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Something went wrong loading images.')),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text("No images uploaded yet.")),
          );
        }

        final images = snapshot.data!.docs;

        return LayoutBuilder(
          builder: (context, c) {
            final cols = _calcCols(c.maxWidth);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 5 / 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: images.length,
              itemBuilder: (context, i) {
                final data = images[i].data() as Map<String, dynamic>?;
                final imageUrl = data?['fileUrl'] as String?;

                if (imageUrl == null || imageUrl.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.white)),
                  );
                }

                return GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => ImageViewModal(
                        imageUrl: imageUrl,
                        imageText: data?['text'],
                        shortCode: data?['shortCode'],
                        imageId: images[i].id,
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                      errorBuilder: (context, _, __) => Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(child: Icon(Icons.error_outline, color: Colors.red)),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: const Center(child: Text('Please log in to see your profile.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: true,
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 8 / 5,
                child: ProfileWidget(
                  currentIndex: _currentIndex,
                  onEditorTapped: () => setState(() => _currentIndex = 0),
                  onFanzinesTapped: () => setState(() => _currentIndex = 1),
                  onPagesTapped: () => setState(() => _currentIndex = 2),
                ),
              ),
              const SizedBox(height: 8),
              if (_currentIndex == 0) _buildEditorSection()
              else if (_currentIndex == 1) _buildFanzinesSection()
              else _buildPagesSection(),
            ],
          ),
        ),
      ),
    );
  }
}