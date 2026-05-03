import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../services/user_provider.dart';
import '../../reader_panels/social_matrix_tab.dart';
import '../components/maker_item_tile.dart';
import '../components/profile_helpers.dart';

class ProfileSettingsTab extends StatelessWidget {
  final int subTabIndex;
  final String targetUserId;
  final TextEditingController loginZineController;
  final TextEditingController registerZineController;
  final VoidCallback onSaveGlobalShortcodes;
  final VoidCallback onShowCreateManagedProfileDialog;

  const ProfileSettingsTab({
    super.key,
    required this.subTabIndex,
    required this.targetUserId,
    required this.loginZineController,
    required this.registerZineController,
    required this.onSaveGlobalShortcodes,
    required this.onShowCreateManagedProfileDialog,
  });

  @override
  Widget build(BuildContext context) {
    if (subTabIndex == 0) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("GLOBAL APP SHORTCODES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 24),
              TextField(controller: loginZineController, decoration: const InputDecoration(labelText: 'Login Zine ShortCode', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 16),
              TextField(controller: registerZineController, decoration: const InputDecoration(labelText: 'Register Zine ShortCode', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 24),
              ElevatedButton(
                  onPressed: onSaveGlobalShortcodes,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text("SAVE CONFIGURATION", style: TextStyle(fontWeight: FontWeight.bold))
              ),
            ],
          ),
        ),
      );
    } else if (subTabIndex == 1) {
      return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('profiles').where('isManaged', isEqualTo: true).where('managers', arrayContains: targetUserId).snapshots(),
          builder: (context, snapshot) {
            final List<Widget> buttons = [
              ProfileQuickActionTile(label: "+ managed profile", color: Colors.grey.shade800, onTap: onShowCreateManagedProfileDialog)
            ];
            if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));

            final docs = snapshot.data!.docs;
            return SliverPadding(
              padding: const EdgeInsets.all(8.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index < buttons.length) return buttons[index];
                  return MakerItemTile(doc: docs[index - buttons.length], shouldEdit: true);
                }, childCount: docs.length + buttons.length),
              ),
            );
          }
      );
    } else if (subTabIndex == 2) {
      final userProvider = context.read<UserProvider>();
      if (!userProvider.isAdmin) {
        return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text("Access restricted to Administrators."))));
      }
      return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('Users').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
            final docs = snapshot.data!.docs;
            return SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final uid = docs[index].id;
                  final userData = docs[index].data() as Map<String, dynamic>;
                  final dynamic rolesData = userData['roles'];
                  final Set<String> selectedRolesSet = rolesData != null
                      ? Set<String>.from(rolesData)
                      : (userData['role'] != null && userData['role'] != 'user' ? {userData['role']} : <String>{});

                  return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('profiles').doc(uid).get(),
                      builder: (context, profileSnap) {
                        final pData = profileSnap.data?.data() as Map?;
                        final name = pData?['displayName'] ?? pData?['username'] ?? 'unknown';
                        final username = pData?['username'] ?? 'unknown';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                          child: ListTile(
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text("UID: $uid", style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                    onTap: () => context.go('/$username'),
                                    child: Text('/$username', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, decoration: TextDecoration.underline))
                                ),
                                const SizedBox(width: 16),
                                SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(value: 'admin', label: Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                    ButtonSegment(value: 'moderator', label: Text('MODERATOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                    ButtonSegment(value: 'curator', label: Text('CURATOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                  ],
                                  selected: selectedRolesSet,
                                  onSelectionChanged: (newSelection) async {
                                    if (!context.read<UserProvider>().isAdmin) return;
                                    final rolesList = newSelection.toList();
                                    final bool isCurator = newSelection.contains('curator');
                                    final bool isAdmin = newSelection.contains('admin');
                                    final bool isModerator = newSelection.contains('moderator');
                                    String legacyRole = 'user';
                                    if (isAdmin) legacyRole = 'admin';
                                    else if (isModerator) legacyRole = 'moderator';
                                    else if (isCurator) legacyRole = 'curator';

                                    final batch = FirebaseFirestore.instance.batch();
                                    batch.update(FirebaseFirestore.instance.collection('Users').doc(uid), {'roles': rolesList, 'role': legacyRole, 'isCurator': isCurator || isAdmin || isModerator});
                                    batch.update(FirebaseFirestore.instance.collection('profiles').doc(uid), {'isCurator': isCurator || isAdmin || isModerator, 'isAdmin': isAdmin});
                                    await batch.commit();
                                  },
                                  multiSelectionEnabled: true,
                                  emptySelectionAllowed: true,
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                  );
                }, childCount: docs.length),
              ),
            );
          }
      );
    } else if (subTabIndex == 3) {
      return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(24.0), child: SocialMatrixTab())));
    }

    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
}