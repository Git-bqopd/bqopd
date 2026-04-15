import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../blocs/profile/profile_bloc.dart';
import '../repositories/user_repository.dart';
import '../repositories/engagement_repository.dart';
import '../services/user_provider.dart';
import '../services/user_bootstrap.dart';
import '../services/username_service.dart';
import '../widgets/profile_widget.dart';
import '../widgets/page_wrapper.dart';
import '../widgets/new_fanzine_modal.dart';
import '../widgets/image_view_modal.dart';
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

    // Intercept URL Query parameters
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
        isViewerEditor: userProvider.isEditor,
        initialTab: initialTab, // Pass starting tab into the BLoC
      )),
      child: _ProfilePageView(initialDrafts: initialDrafts),
    );
  }
}

class _ProfilePageView extends StatefulWidget {
  final bool initialDrafts;

  const _ProfilePageView({this.initialDrafts = false});

  @override
  State<_ProfilePageView> createState() => _ProfilePageViewState();
}

class _ProfilePageViewState extends State<_ProfilePageView> {
  // Local state for Pages/Maker tab sub-filter
  bool _showDrafts = false;

  // Local state for Editor tab sub-filter
  int _editorSubTabIndex = 0;

  bool _isUploadingPdf = false;

  @override
  void initState() {
    super.initState();
    _showDrafts = widget.initialDrafts; // Seed initial value
  }

  @override
  void didUpdateWidget(covariant _ProfilePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ensure hot-updates from URL are properly caught if Widget isn't completely disposed
    if (oldWidget.initialDrafts != widget.initialDrafts) {
      setState(() {
        _showDrafts = widget.initialDrafts;
      });
    }
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

  void _showNewFanzineModal(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewFanzineModal(userId: userId),
    );
  }

  void _showImageUpload(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageUploadModal(userId: userId),
    );
  }

  void _showMakerCreateModal(String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => MakerCreateModal(
        onSingleImage: () => _createFolio(userId, isSingleImage: true),
        onCreateFolio: () => _createFolio(userId, isSingleImage: false),
      ),
    );
  }

  Future<void> _createFolio(String userId, {bool isSingleImage = false}) async {
    try {
      final db = FirebaseFirestore.instance;
      final folioRef = db.collection('fanzines').doc();

      final shortCode = folioRef.id.substring(0, 7);

      await folioRef.set({
        'title': isSingleImage ? 'Single Image' : 'New Folio',
        'editorId': userId,
        'status': 'working',
        'processingStatus': 'complete',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'folio',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': false,
      });

      if (mounted) context.push('/editor/${folioRef.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteFanzine(String fanzineId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Draft?"),
        content: const Text("This will permanently remove this draft and its pages."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable('delete_fanzine')
          .call({'fanzineId': fanzineId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Draft deleted.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _createCalendarFanzine(String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final fanzineRef = db.collection('fanzines').doc();

      final shortCode = fanzineRef.id.substring(0, 7);

      await fanzineRef.set({
        'title': 'Convention Calendar 2026',
        'editorId': userId,
        'status': 'working',
        'processingStatus': 'complete',
        'creationDate': FieldValue.serverTimestamp(),
        'type': 'calendar',
        'shortCode': shortCode,
        'shortCodeKey': shortCode.toUpperCase(),
        'twoPage': true,
      });

      await fanzineRef.collection('pages').add({
        'pageNumber': 1,
        'templateId': 'calendar_left',
        'status': 'ready',
      });
      await fanzineRef.collection('pages').add({
        'pageNumber': 2,
        'templateId': 'calendar_right',
        'status': 'ready',
      });

      if (mounted) context.push('/editor/${fanzineRef.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _handlePdfUpload(String userId) async {
    if (_isUploadingPdf) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null) {
        setState(() => _isUploadingPdf = true);

        PlatformFile file = result.files.first;
        Uint8List? fileBytes = file.bytes;
        String fileName = file.name;

        if (fileBytes != null) {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('uploads/raw_pdfs/$fileName');

          final metadata = SettableMetadata(
            contentType: 'application/pdf',
            customMetadata: {
              'uploaderId': userId,
              'originalName': fileName,
            },
          );

          await storageRef.putData(fileBytes, metadata);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Uploaded "$fileName". Curator processing started.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload Error: $e')),
        );
      }
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: Colors.red),
            );
          }
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.userData == null) {
            return const Center(child: Text("Profile not found."));
          }

          final userData = state.userData!;
          final targetUserId = userData['uid'];
          final isOwner =
              context.read<UserProvider>().currentUserId == targetUserId;
          final canEditProfile = _canEdit(userData);
          final activeTab = state.visibleTabs.isEmpty
              ? 'collection'
              : state.visibleTabs[state.currentTabIndex];

          final bool isThisUserAnEditor =
              userData['Editor'] == true || userData['isEditor'] == true;
          final bool amIAnEditor =
              (context.read<UserProvider>().isEditor == true) ||
                  (isOwner && isThisUserAnEditor);

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
                        onFollowToggle: () => context
                            .read<ProfileBloc>()
                            .add(ToggleFollowRequested()),
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
                            context
                                .read<ProfileBloc>()
                                .add(ChangeTabRequested(idx));
                            setState(() {
                              _showDrafts = false;
                              _editorSubTabIndex = 0;
                            });
                          },
                          canEdit: canEditProfile,
                          onUploadImage: () => _showImageUpload(targetUserId),
                        ),
                      ),
                    ),
                  ),

                  // Sub-navigation for Editor Tab
                  if (activeTab == 'editor' && canEditProfile && isOwner)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                                bottom: BorderSide(color: Colors.black12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _isUploadingPdf
                                    ? null
                                    : () => _handlePdfUpload(targetUserId),
                                child: Text(
                                  _isUploadingPdf
                                      ? "uploading..."
                                      : "upload PDF",
                                  style: const TextStyle(color: Colors.black),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text("|",
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _editorSubTabIndex = 0),
                                child: Text(
                                  "curator",
                                  style: TextStyle(
                                    color: _editorSubTabIndex == 0
                                        ? Colors.black
                                        : Colors.grey,
                                    fontWeight: _editorSubTabIndex == 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    decoration: _editorSubTabIndex == 0
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text("|",
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _editorSubTabIndex = 1),
                                child: Text(
                                  "publisher",
                                  style: TextStyle(
                                    color: _editorSubTabIndex == 1
                                        ? Colors.black
                                        : Colors.grey,
                                    fontWeight: _editorSubTabIndex == 1
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    decoration: _editorSubTabIndex == 1
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text("|",
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _editorSubTabIndex = 2),
                                child: Text(
                                  "entities",
                                  style: TextStyle(
                                    color: _editorSubTabIndex == 2
                                        ? Colors.black
                                        : Colors.grey,
                                    fontWeight: _editorSubTabIndex == 2
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    decoration: _editorSubTabIndex == 2
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Sub-navigation for Maker Tab
                  if (activeTab == 'maker' && canEditProfile && isOwner)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                                bottom: BorderSide(color: Colors.black12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () => _showMakerCreateModal(targetUserId),
                                child: const Text("make",
                                    style: TextStyle(color: Colors.black)),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text("|",
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = false),
                                child: Text(
                                  "published",
                                  style: TextStyle(
                                    color: !_showDrafts
                                        ? Colors.black
                                        : Colors.grey,
                                    fontWeight: !_showDrafts
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    decoration: !_showDrafts
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text("|",
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = true),
                                child: Text(
                                  "drafts",
                                  style: TextStyle(
                                    color: _showDrafts
                                        ? Colors.black
                                        : Colors.grey,
                                    fontWeight: _showDrafts
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    decoration: _showDrafts
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Sub-navigation for Pages Tab (Legacy)
                  if (activeTab == 'pages' && canEditProfile && isOwner)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabsDelegate(
                        child: Container(
                          height: 50,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                                bottom: BorderSide(color: Colors.black12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () => _showImageUpload(targetUserId),
                                child: const Text("upload image",
                                    style: TextStyle(color: Colors.black)),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text("|",
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = false),
                                child: Text(
                                  "published pages",
                                  style: TextStyle(
                                    color: !_showDrafts
                                        ? Colors.black
                                        : Colors.grey,
                                    fontWeight: !_showDrafts
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    decoration: !_showDrafts
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text("|",
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _showDrafts = true),
                                child: Text(
                                  "draft pages",
                                  style: TextStyle(
                                    color: _showDrafts
                                        ? Colors.black
                                        : Colors.grey,
                                    fontWeight: _showDrafts
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    decoration: _showDrafts
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  _buildContentSliver(targetUserId, isOwner, amIAnEditor, activeTab),

                  const SliverToBoxAdapter(child: SizedBox(height: 64)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContentSliver(
      String targetUserId, bool isOwner, bool isEditor, String activeTab) {
    Stream<List<QueryDocumentSnapshot>>? stream;
    Widget? placeholder;

    switch (activeTab) {
      case 'editor': // EDITOR
        if (!isOwner && !isEditor) {
          return const SliverToBoxAdapter(child: SizedBox());
        }

        if (_editorSubTabIndex == 2) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('fanzines')
                .where('status', whereIn: ['draft', 'working']).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                    child: Center(child: Text("Error: ${snapshot.error}")));
              }
              if (!snapshot.hasData) {
                return const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()));
              }

              final Map<String, int> entityCounts = {};
              for (var doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final entities = List<String>.from(data['draftEntities'] ?? []);
                for (var name in entities) {
                  entityCounts[name] = (entityCounts[name] ?? 0) + 1;
                }
              }

              if (entityCounts.isEmpty) {
                return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(child: Text("No entities found in current drafts.")),
                    ));
              }

              final sortedNames = entityCounts.keys.toList()
                ..sort((a, b) {
                  int countCompare = entityCounts[b]!.compareTo(entityCounts[a]!);
                  if (countCompare != 0) return countCompare;
                  return a.compareTo(b);
                });

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final name = sortedNames[index];
                      final count = entityCounts[name]!;
                      return Column(
                        children: [
                          _EntityRow(name: name, count: count),
                          if (index < sortedNames.length - 1)
                            const Divider(height: 1),
                        ],
                      );
                    },
                    childCount: sortedNames.length,
                  ),
                ),
              );
            },
          );
        }

        // Fetch all user zines and filter client-side to avoid index requirements
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .snapshots()
            .map((snap) {
          final List<QueryDocumentSnapshot> filtered = snap.docs.where((doc) {
            final data = doc.data();

            final hasSourceFile = data.containsKey('sourceFile');
            final isLive = data['status'] == 'live';

            if (_editorSubTabIndex == 0) {
              return hasSourceFile && !isLive;
            } else {
              final isUserInvolved = data['editorId'] == targetUserId ||
                  data['uploaderId'] == targetUserId;
              if (!isUserInvolved) return false;
              if (data['type'] == 'folio') return false;
              return !hasSourceFile || isLive;
            }
          }).toList();

          filtered.sort((a, b) {
            final aT = (a.data() as Map)['creationDate'] as Timestamp?;
            final bT = (b.data() as Map)['creationDate'] as Timestamp?;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          });

          return filtered;
        });
        break;
      case 'maker': // MAKER - Dedicated Folios Feed
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('editorId', isEqualTo: targetUserId)
            .snapshots()
            .map((snap) {
          final List<QueryDocumentSnapshot> filtered = snap.docs.where((doc) {
            final data = doc.data();
            if (data['type'] != 'folio') return false;

            final isLive = data['status'] == 'live' || data['status'] == 'published';

            if (isOwner) {
              return _showDrafts ? !isLive : isLive;
            }
            return isLive;
          }).toList();

          filtered.sort((a, b) {
            final aT = (a.data() as Map)['creationDate'] as Timestamp?;
            final bT = (b.data() as Map)['creationDate'] as Timestamp?;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          });

          return filtered;
        });
        break;
      case 'pages': // Legacy loose images feed
        stream = FirebaseFirestore.instance
            .collection('images')
            .where('uploaderId', isEqualTo: targetUserId)
            .orderBy('timestamp', descending: true)
            .snapshots()
            .map((snap) {
          if (isOwner) {
            if (_showDrafts) {
              return snap.docs.where((doc) {
                final data = doc.data();
                return data['status'] == 'pending';
              }).toList();
            } else {
              return snap.docs.where((doc) {
                final data = doc.data();
                return data['status'] != 'pending';
              }).toList();
            }
          }
          return snap.docs.where((doc) {
            final data = doc.data();
            return data['status'] != 'pending';
          }).toList();
        });
        break;
      case 'works': // WORKS
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('editorId', isEqualTo: targetUserId)
            .orderBy('creationDate', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;
      case 'comments': // COMMENTS
        placeholder = const Center(
            child: Text("Letters of Comment functionality coming soon."));
        break;
      case 'mentions': // MENTIONS
        stream = FirebaseFirestore.instance
            .collection('fanzines')
            .where('mentionedUsers', arrayContains: 'user:$targetUserId')
            .orderBy('creationDate', descending: true)
            .snapshots()
            .map((snap) => snap.docs);
        break;
      case 'collection': // COLLECTION
      default:
        placeholder = const Center(child: Text("User collection coming soon."));
        break;
    }

    if (placeholder != null) {
      return SliverToBoxAdapter(
          child: SizedBox(height: 200, child: placeholder));
    }

    if (stream == null) return const SliverToBoxAdapter(child: SizedBox());

    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: stream,
      builder: (context, snapshot) {
        final buttons = <Widget>[];
        if (activeTab == 'editor' && isOwner && _editorSubTabIndex == 1) {
          if (isEditor) {
            buttons.add(TextButton(
                style: TextButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero)),
                onPressed: () => _showNewFanzineModal(targetUserId),
                child: const Text("make new fanzine",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white))));

            buttons.add(TextButton(
                style: TextButton.styleFrom(
                    backgroundColor: Colors.purple,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero)),
                onPressed: () => _createCalendarFanzine(targetUserId),
                child: const Text("con calendar",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white))));
          }
          buttons.add(TextButton(
              style: TextButton.styleFrom(
                  backgroundColor: Colors.grey,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero)),
              onPressed: () => context.pushNamed('settings'),
              child: const Text("settings",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white))));
        }

        if (snapshot.hasError) {
          return SliverToBoxAdapter(
              child: Center(child: Text("Error: ${snapshot.error}")));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()));
        }

        final docs = snapshot.data ?? [];
        final totalItems = buttons.length + docs.length;

        if (totalItems == 0) {
          String emptyMsg = "No items found.";
          if (activeTab == 'maker' && isOwner) {
            emptyMsg =
            _showDrafts ? "No pending folios." : "No published folios.";
          } else if (activeTab == 'pages' && isOwner) {
            emptyMsg =
            _showDrafts ? "No pending drafts." : "No published pages.";
          } else if (activeTab == 'editor' && isOwner) {
            emptyMsg = _editorSubTabIndex == 0
                ? "No zines in curator queue."
                : "No live fanzines.";
          }
          return SliverToBoxAdapter(
              child:
              SizedBox(height: 100, child: Center(child: Text(emptyMsg))));
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 5 / 8,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                if (index < buttons.length) return buttons[index];

                final docIndex = index - buttons.length;
                final doc = docs[docIndex];
                final data = doc.data() as Map<String, dynamic>;
                final docId = doc.id;

                if (activeTab == 'editor' ||
                    activeTab == 'works' ||
                    activeTab == 'mentions' ||
                    activeTab == 'maker') {
                  return _FanzineCoverTile(
                    fanzineId: docId,
                    title: data['title'] ?? 'Untitled',
                    type: data['type'] ?? 'fanzine',
                    shouldEdit: activeTab == 'editor' || activeTab == 'maker',
                    isDraft: _showDrafts && activeTab == 'maker',
                    onDelete: () => _deleteFanzine(docId),
                  );
                } else {
                  String? imageUrl = data['fileUrl'];
                  if (imageUrl == null || imageUrl.isEmpty) {
                    return const SizedBox();
                  }

                  return GestureDetector(
                    onTap: () {
                      showDialog(
                          context: context,
                          builder: (_) => ImageViewModal(
                              imageUrl: imageUrl,
                              imageText: data['text'],
                              shortCode: data['shortCode'],
                              imageId: docId));
                    },
                    child: ClipRect(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Center(
                              child: Icon(Icons.broken_image, color: Colors.grey)),
                        )),
                  );
                }
              },
              childCount: totalItems,
            ),
          ),
        );
      },
    );
  }
}

class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ProfileTabsDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(elevation: overlapsContent ? 4 : 0, child: child);
  }

  @override
  double get maxExtent => 50.0;

  @override
  double get minExtent => 50.0;

  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) => true;
}

class _FanzineCoverTile extends StatelessWidget {
  final String fanzineId;
  final String title;
  final String type;
  final bool shouldEdit;
  final bool isDraft;
  final VoidCallback? onDelete;

  const _FanzineCoverTile({
    required this.fanzineId,
    required this.title,
    this.type = 'fanzine',
    this.shouldEdit = false,
    this.isDraft = false,
    this.onDelete,
  });

  Future<String?> _fetchCoverUrl() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('fanzines')
          .doc(fanzineId)
          .collection('pages')
          .orderBy('pageNumber')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final storagePath = data['storagePath'];
        if (storagePath != null && storagePath.toString().isNotEmpty) {
          try {
            return await FirebaseStorage.instance
                .ref(storagePath)
                .getDownloadURL();
          } catch (_) {}
        }
        return data['imageUrl'];
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _fetchCoverUrl(),
      builder: (context, snapshot) {
        final bool isLoading =
            snapshot.connectionState == ConnectionState.waiting;
        final imageUrl = snapshot.data;

        return GestureDetector(
          onTap: () {
            if (shouldEdit) {
              context.push('/editor/$fanzineId');
            } else {
              context.push('/reader/$fanzineId');
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Image.network(imageUrl, fit: BoxFit.cover)
                else if (isLoading)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (type == 'folio' || type == 'calendar')
                    Container(
                      color: Colors.grey[200],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_document, size: 40, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              "Draft\n(No Cover)",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey[200],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.pending_actions,
                              size: 40, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              "Ingesting...",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                    child: Text(
                      title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // Draft Deletion Button (X)
                if (isDraft && onDelete != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EntityRow extends StatelessWidget {
  final String name;
  final int count;

  const _EntityRow({required this.name, required this.count});

  @override
  Widget build(BuildContext context) {
    final handle = normalizeHandle(name);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('usernames')
          .doc(handle)
          .snapshots(),
      builder: (context, snapshot) {
        Widget statusWidget;

        if (!snapshot.hasData) {
          statusWidget = const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String linkText = '/$handle';

          if (data['isAlias'] == true) {
            final redirect = data['redirect'] ?? 'unknown';
            linkText = '/$handle -> /$redirect';
          }

          statusWidget = InkWell(
            onTap: () => context.go('/$handle'),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                linkText,
                style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline),
              ),
            ),
          );
        } else {
          statusWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _createProfile(context, name),
                child:
                const Text("Create", style: TextStyle(color: Colors.green)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _createAlias(context, name),
                child:
                const Text("Alias", style: TextStyle(color: Colors.orange)),
              ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(count.toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              Expanded(
                child: Text(name, style: const TextStyle(fontSize: 16)),
              ),
              statusWidget,
            ],
          ),
        );
      },
    );
  }

  Future<void> _createProfile(BuildContext context, String name) async {
    String first = name;
    String last = "";

    if (name.contains(' ')) {
      final parts = name.split(' ');
      first = parts.first;
      last = parts.sublist(1).join(' ');
    }

    try {
      await createManagedProfile(
          firstName: first, lastName: last, bio: "Auto-created from profile dashboard");
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Profile Created!")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _createAlias(BuildContext context, String name) async {
    final target = await showDialog<String>(
        context: context,
        builder: (c) {
          final controller = TextEditingController();
          return AlertDialog(
            title: Text("Create Alias for '$name'"),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text("Enter EXISTING username (target):"),
              TextField(
                  controller: controller,
                  decoration:
                  const InputDecoration(hintText: "e.g. julius-schwartz"))
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text("Cancel")),
              TextButton(
                  onPressed: () => Navigator.pop(c, controller.text.trim()),
                  child: const Text("Create Alias")),
            ],
          );
        });

    if (target == null || target.isEmpty) return;

    try {
      await createAlias(aliasHandle: name, targetHandle: target);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Alias Created!")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }
}