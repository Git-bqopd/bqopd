import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FollowListModal extends StatefulWidget {
  final String userId;
  final String title; // "Followers" or "Following"
  final String collectionName; // "followers" or "following"

  const FollowListModal({
    super.key,
    required this.userId,
    required this.title,
    required this.collectionName,
  });

  @override
  State<FollowListModal> createState() => _FollowListModalState();
}

class _FollowListModalState extends State<FollowListModal> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Center(
        child: Container(
          color: const Color(0xFFF1B255), // Manilla Envelope Color
          padding: const EdgeInsets.all(16.0),
          child: AspectRatio(
            aspectRatio: 5 / 8, // Sticker Ratio
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 40), // Balancer
                        Text(widget.title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                      decoration: InputDecoration(
                        hintText: "Search",
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey[100],
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  // List
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('Users')
                          .doc(widget.userId)
                          .collection(widget.collectionName)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                        final docs = snapshot.data!.docs;
                        if (docs.isEmpty) {
                          return Center(
                            child: Text("No ${widget.title.toLowerCase()} yet.",
                                style: const TextStyle(color: Colors.grey)),
                          );
                        }

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final uid = docs[index].id;
                            return _UserListTile(uid: uid, searchQuery: _searchQuery);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserListTile extends StatelessWidget {
  final String uid;
  final String searchQuery;

  const _UserListTile({required this.uid, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('Users').doc(uid).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const SizedBox.shrink();

        final username = data['username'] ?? '';
        final displayName = data['displayName'] ?? '';
        final firstName = data['firstName'] ?? '';
        final lastName = data['lastName'] ?? '';
        final fullName = displayName.isNotEmpty ? displayName : "$firstName $lastName".trim();
        final photoUrl = data['photoUrl'];

        // Filter
        if (searchQuery.isNotEmpty &&
            !username.toLowerCase().contains(searchQuery) &&
            !fullName.toLowerCase().contains(searchQuery)) {
          return const SizedBox.shrink();
        }

        return ListTile(
          onTap: () {
            Navigator.pop(context);
            context.push('/$username');
          },
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null ? const Icon(Icons.person, color: Colors.grey) : null,
          ),
          title: Text(fullName.isNotEmpty ? fullName : username,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: Text("@$username", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          trailing: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () {
              Navigator.pop(context);
              context.push('/$username');
            },
            child: const Text("View", style: TextStyle(fontSize: 12, color: Colors.black)),
          ),
        );
      },
    );
  }
}