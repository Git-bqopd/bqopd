import 'package:bqopd/widgets/page_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../widgets/profile_widget.dart';
import '../widgets/new_fanzine_modal.dart';
import '../widgets/image_view_modal.dart';
import '../widgets/login_widget.dart';
import '../widgets/fanzine_widget.dart';
import 'fanzine_editor_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  final String? userId; // Optional: If null, uses current user
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // 0 = Editor, 1 = Fanzines, 2 = Pages
  int _currentIndex = 0;

  // State
  bool _isOwner = false;
  bool _isEditor = false;
  String? _targetUserId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _initUser();
    }
  }

  Future<void> _initUser() async {
    setState(() => _isLoading = true);

    final currentUser = FirebaseAuth.instance.currentUser;

    // 1. Determine Target User
    if (widget.userId != null) {
      _targetUserId = widget.userId;
    } else {
      _targetUserId = currentUser?.uid;
    }

    // 2. Determine Permissions
    if (currentUser != null && _targetUserId == currentUser.uid) {
      _isOwner = true;
      // Fetch editor status
      try {
        final doc = await FirebaseFirestore.instance.collection('Users').doc(currentUser.uid).get();
        if (doc.exists && mounted) {
          setState(() => _isEditor = (doc.data()?['Editor'] == true));
        }
      } catch (e) {
        print("Error fetching editor status: $e");
      }
    } else {
      _isOwner = false;
      _isEditor = false;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showNewFanzineModal() {
    if (!_isOwner || _targetUserId == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewFanzineModal(userId: _targetUserId!),
    );
  }

  ButtonStyle get _blueButtonStyle => TextButton.styleFrom(
    backgroundColor: Colors.blueAccent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    // Handling cases where no user is found (e.g. not logged in and no ID passed)
    if (!_isLoading && _targetUserId == null) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
        body: Center(
          child: LoginWidget(onTap: () => context.go('/login')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: SafeArea(
        child: PageWrapper(
          maxWidth: 1000,
          scroll: false, // We handle scrolling manually
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Profile Widget (Fixed Height)
                if (_targetUserId != null)
                  SizedBox(
                    height: 340,
                    child: ProfileWidget(
                      targetUserId: _targetUserId!,
                      currentIndex: _currentIndex,
                      onEditorTapped: () => setState(() => _currentIndex = 0),
                      onFanzinesTapped: () => setState(() => _currentIndex = 1),
                      onPagesTapped: () => setState(() => _currentIndex = 2),
                    ),
                  ),

                const SizedBox(height: 16),

                // 2. The Content Grid
                if (_targetUserId != null) _buildContentGrid(),

                const SizedBox(height: 32),

                // 3. Bottom Widget (Navigation or Login Call-to-Action)
                if (!_isOwner)
                  FirebaseAuth.instance.currentUser == null
                      ? LoginWidget(onTap: () => context.go('/register'))
                      : const FanzineWidget() // Show nav bar if logged in but looking at someone else
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentGrid() {
    // --- TAB 1: FANZINES (Consumed Content - Placeholder) ---
    if (_currentIndex == 1) {
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 5 / 8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          Container(
            decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(8),
            child: const Text("For You Zine Issue 3", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          for (int i = 0; i < 3; i++)
            Container(decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12))),
        ],
      );
    }

    // --- TAB 0 (Editor) & TAB 2 (Pages) use Queries ---
    Query query;
    if (_currentIndex == 0) {
      query = FirebaseFirestore.instance.collection('fanzines').where('editorId', isEqualTo: _targetUserId).orderBy('creationDate', descending: true);
    } else {
      query = FirebaseFirestore.instance.collection('images').where('uploaderId', isEqualTo: _targetUserId).orderBy('timestamp', descending: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {

        // --- EDITOR DASHBOARD BUTTONS (Only if Owner & Editor) ---
        final buttons = <Widget>[];
        if (_currentIndex == 0 && _isOwner) {
          if (_isEditor) {
            buttons.add(TextButton(style: _blueButtonStyle, onPressed: _showNewFanzineModal, child: const Text("make new fanzine", textAlign: TextAlign.center, style: TextStyle(color: Colors.white))));
          } else {
            buttons.add(Container(padding: const EdgeInsets.all(8), color: Colors.red[100], alignment: Alignment.center, child: const Text("You are not an editor.", textAlign: TextAlign.center)));
          }
          buttons.add(TextButton(style: TextButton.styleFrom(backgroundColor: Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())), child: const Text("settings", textAlign: TextAlign.center, style: TextStyle(color: Colors.white))));
        }

        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];
        final totalItems = buttons.length + docs.length;

        if (totalItems == 0) return const SizedBox(height: 100, child: Center(child: Text("No content found.")));

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 5 / 8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index < buttons.length) return buttons[index];

            final docIndex = index - buttons.length;
            final data = docs[docIndex].data() as Map<String, dynamic>;

            if (_currentIndex == 0) {
              final title = data['title'] ?? 'Untitled';
              return TextButton(
                style: _blueButtonStyle,
                onPressed: () { if (_isOwner) Navigator.push(context, MaterialPageRoute(builder: (_) => FanzineEditorPage(fanzineId: docs[docIndex].id))); },
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
              );
            } else {
              final url = data['fileUrl'] ?? '';
              if (url.isEmpty) return const SizedBox();
              return GestureDetector(
                onTap: () {
                  showDialog(context: context, builder: (_) => ImageViewModal(imageUrl: url, imageText: data['text'], shortCode: data['shortCode'], imageId: docs[docIndex].id));
                },
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url, fit: BoxFit.cover)),
              );
            }
          },
        );
      },
    );
  }
}