import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../blocs/profile/profile_bloc.dart';
import '../repositories/user_repository.dart';
import '../repositories/engagement_repository.dart';
import '../services/user_provider.dart';
import '../widgets/profile_widget.dart';
import '../widgets/page_wrapper.dart';
import '../widgets/image_upload_modal.dart';

class ProfilePage extends StatelessWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUid = userProvider.currentUserId;
    final targetUserId = userId ?? currentUid;

    if (!userProvider.isLoading && targetUserId == null) {
      return const Scaffold(body: Center(child: Text("Please log in.")));
    }

    final queryParams = GoRouterState.of(context).uri.queryParameters;
    final initialTab = queryParams['tab'];
    final initialDrafts = queryParams['drafts'] == 'true';

    return BlocProvider(
      create: (context) => ProfileBloc(
        userRepository: context.read<UserRepository>(),
        engagementRepository: context.read<EngagementRepository>(),
      )..add(LoadProfileRequested(
        userId: targetUserId!,
        currentAuthId: currentUid ?? '',
        isViewerModerator: userProvider.isModerator,
        isViewerCurator: userProvider.isCurator,
        initialTab: initialTab,
      )),
      child: _ProfilePageView(initialDrafts: initialDrafts),
    );
  }
}

class _ProfilePageView extends StatefulWidget {
  final bool initialDrafts;
  // FIXED: Removed unused super.key from private constructor to resolve warning
  const _ProfilePageView({this.initialDrafts = false});

  @override
  State<_ProfilePageView> createState() => _ProfilePageViewState();
}

class _ProfilePageViewState extends State<_ProfilePageView> {
  bool _showDrafts = false;
  int _curatorSubTabIndex = 0;
  bool _isUploadingPdf = false;

  @override
  void initState() {
    super.initState();
    _showDrafts = widget.initialDrafts;
  }

  bool _canEdit(Map<String, dynamic> userData) {
    final provider = Provider.of<UserProvider>(context, listen: false);
    final currentUid = provider.currentUserId;
    if (currentUid == null) return false;
    if (userData['uid'] == currentUid) return true;
    final managers = List<String>.from(userData['managers'] ?? []);
    if ((userData['isManaged'] == true) && managers.contains(currentUid)) {
      return true;
    }
    return false;
  }

  void _showImageUpload(String userId) {
    showDialog(context: context, barrierDismissible: false, builder: (_) => ImageUploadModal(userId: userId));
  }

  Future<void> _handlePdfUpload(String userId) async {
    if (_isUploadingPdf) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
      if (result != null) {
        setState(() => _isUploadingPdf = true);
        PlatformFile file = result.files.first;
        Uint8List? fileBytes = file.bytes;
        if (fileBytes != null) {
          final storageRef = FirebaseStorage.instance.ref().child('uploads/raw_pdfs/${file.name}');
          final metadata = SettableMetadata(contentType: 'application/pdf', customMetadata: {'uploaderId': userId, 'originalName': file.name});
          await storageRef.putData(fileBytes, metadata);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded "${file.name}". Curator processing started.')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload Error: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: BlocConsumer<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red));
          }
        },
        builder: (context, state) {
          if (state.isLoading) return const Center(child: CircularProgressIndicator());
          if (state.userData == null) return const Center(child: Text("Profile not found."));

          final userData = state.userData!;
          final targetUserId = userData['uid'];
          final isOwner = context.read<UserProvider>().currentUserId == targetUserId;
          final canEditProfile = _canEdit(userData);
          final activeTab = state.visibleTabs.isEmpty ? 'collection' : state.visibleTabs[state.currentTabIndex];

          return SafeArea(
            child: PageWrapper(
              maxWidth: 900,
              scroll: false,
              padding: EdgeInsets.zero,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ProfileHeader(
                        userData: userData,
                        profileUid: targetUserId,
                        isMe: isOwner,
                        isFollowing: state.isFollowing,
                        onFollowToggle: () => context.read<ProfileBloc>().add(ToggleFollowRequested()),
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProfileTabsDelegate(
                      child: SizedBox(
                        height: 50,
                        child: ProfileNavBar(
                          tabTitles: state.visibleTabs,
                          currentIndex: state.currentTabIndex,
                          onTabChanged: (idx) {
                            context.read<ProfileBloc>().add(ChangeTabRequested(idx));
                            setState(() { _showDrafts = false; _curatorSubTabIndex = 0; });
                          },
                          canEdit: canEditProfile,
                          onUploadImage: () => _showImageUpload(targetUserId),
                        ),
                      ),
                    ),
                  ),

                  if (activeTab == 'curator')
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _isUploadingPdf ? null : () => _handlePdfUpload(targetUserId),
                                child: Text(_isUploadingPdf ? "uploading..." : "upload PDF", style: const TextStyle(color: Colors.black)),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("curator", 0),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("publisher", 1),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("|", style: TextStyle(color: Colors.grey))),
                              _buildSubTab("entities", 2),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  _buildContentSliver(targetUserId, isOwner, activeTab),
                  const SliverToBoxAdapter(child: SizedBox(height: 64)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubTab(String label, int index) {
    final isActive = _curatorSubTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _curatorSubTabIndex = index),
      child: Text(label, style: TextStyle(color: isActive ? Colors.black : Colors.grey, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, decoration: isActive ? TextDecoration.underline : null)),
    );
  }

  Widget _buildContentSliver(String targetUserId, bool isOwner, String activeTab) {
    Stream<List<QueryDocumentSnapshot>>? stream;

    switch (activeTab) {
      case 'curator':
        stream = FirebaseFirestore.instance.collection('fanzines').snapshots().map((snap) {
          final List<QueryDocumentSnapshot> filtered = snap.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final hasSource = data.containsKey('sourceFile');
            final isLive = data['status'] == 'live';
            if (_curatorSubTabIndex == 0) return hasSource && !isLive;
            return (!hasSource || isLive) && (data['ownerId'] == targetUserId || (data['editors'] as List? ?? []).contains(targetUserId));
          }).toList();
          // FIXED: Cleaned up unnecessary casts
          filtered.sort((a, b) => (b.data() as Map)['creationDate'].compareTo((a.data() as Map)['creationDate']));
          return filtered;
        });
        break;
      case 'maker':
        stream = FirebaseFirestore.instance.collection('fanzines').where('ownerId', isEqualTo: targetUserId).snapshots().map((snap) {
          final List<QueryDocumentSnapshot> filtered = snap.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['type'] != 'folio') return false;
            final isLive = data['status'] == 'live' || data['status'] == 'published';
            return _showDrafts ? !isLive : isLive;
          }).toList();
          return filtered;
        });
        break;
      default:
        return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("Coming Soon"))));
    }

    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        final docs = snapshot.data!;
        if (docs.isEmpty) return const SliverToBoxAdapter(child: SizedBox(height: 100, child: Center(child: Text("No items found"))));

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
            delegate: SliverChildBuilderDelegate((context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return _FanzineCoverTile(fanzineId: docs[index].id, title: data['title'] ?? 'Untitled', shouldEdit: activeTab == 'curator' || activeTab == 'maker');
            }, childCount: docs.length),
          ),
        );
      },
    );
  }
}

class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ProfileTabsDelegate({required this.child});
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Material(elevation: overlapsContent ? 4 : 0, child: child);
  @override double get maxExtent => 50.0;
  @override double get minExtent => 50.0;
  @override bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) => true;
}

class _FanzineCoverTile extends StatelessWidget {
  final String fanzineId;
  final String title;
  final bool shouldEdit;

  // FIXED: Removed unused super.key from private constructor to resolve warning
  const _FanzineCoverTile({required this.fanzineId, required this.title, this.shouldEdit = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(shouldEdit ? '/editor/$fanzineId' : '/reader/$fanzineId'),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.grey[200], child: const Icon(Icons.menu_book, color: Colors.black12, size: 40)),
            Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), color: Colors.black54, child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis))),
          ],
        ),
      ),
    );
  }
}