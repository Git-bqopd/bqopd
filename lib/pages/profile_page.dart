import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/profile/profile_bloc.dart';
import '../repositories/user_repository.dart';
import '../repositories/engagement_repository.dart';
import '../services/user_provider.dart';
import '../widgets/profile_widget.dart';
import '../widgets/page_wrapper.dart';

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

    return BlocProvider(
      create: (context) => ProfileBloc(
        userRepository: context.read<UserRepository>(),
        engagementRepository: context.read<EngagementRepository>(),
      )..add(LoadProfileRequested(
        userId: targetUserId!,
        currentAuthId: currentUid ?? '',
        isViewerEditor: userProvider.isEditor,
      )),
      child: const _ProfilePageView(),
    );
  }
}

class _ProfilePageView extends StatelessWidget {
  const _ProfilePageView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: BlocConsumer<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red),
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
                        userData: state.userData!,
                        profileUid: state.userData!['uid'],
                        isMe: context.read<UserProvider>().currentUserId == state.userData!['uid'],
                        isFollowing: state.isFollowing,
                        onFollowToggle: () => context.read<ProfileBloc>().add(ToggleFollowRequested()),
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProfileTabsDelegate(
                      child: ProfileNavBar(
                        tabTitles: state.visibleTabs,
                        currentIndex: state.currentTabIndex,
                        onTabChanged: (idx) => context.read<ProfileBloc>().add(ChangeTabRequested(idx)),
                        canEdit: false,
                        onUploadImage: () {},
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  _ProfileContentSliver(state: state),
                  const SliverToBoxAdapter(child: SizedBox(height: 64)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileContentSliver extends StatelessWidget {
  final ProfileState state;
  const _ProfileContentSliver({required this.state});

  @override
  Widget build(BuildContext context) {
    final activeTab = state.visibleTabs.isEmpty ? 'collection' : state.visibleTabs[state.currentTabIndex];

    switch (activeTab) {
      case 'editor':
        return const SliverToBoxAdapter(child: Center(child: Text("Editor Tab Content")));
      case 'pages':
        return const SliverToBoxAdapter(child: Center(child: Text("Pages Tab Content")));
      case 'works':
        return const SliverToBoxAdapter(child: Center(child: Text("Works Tab Content")));
      case 'mentions':
        return const SliverToBoxAdapter(child: Center(child: Text("Mentions Tab Content")));
      default:
        return const SliverToBoxAdapter(child: Center(child: Text("Collection (Coming Soon)")));
    }
  }
}

class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ProfileTabsDelegate({required this.child});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(elevation: overlapsContent ? 4 : 0, child: child);
  }

  @override
  double get maxExtent => 50.0;
  @override
  double get minExtent => 50.0;
  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) => true;
}