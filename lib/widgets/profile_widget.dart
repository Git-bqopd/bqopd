import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> userData;
  final String profileUid;
  final bool isMe;
  final bool isFollowing;
  final VoidCallback onFollowToggle;

  const ProfileHeader({
    super.key,
    required this.userData,
    required this.profileUid,
    required this.isMe,
    required this.isFollowing,
    required this.onFollowToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final content = isMobile ? _buildMobileLayout() : _buildDesktopLayout();
        return Container(
          color: const Color(0xFFF1B255),
          padding: const EdgeInsets.all(16.0),
          child: content,
        );
      },
    );
  }

  Widget _buildDesktopLayout() {
    return AspectRatio(
      aspectRatio: 8 / 3.5,
      child: Container(
        decoration: _whiteBoxDecoration,
        padding: const EdgeInsets.all(24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildInfoSection()),
            const VerticalDivider(width: 48, thickness: 1, color: Colors.black12),
            Expanded(child: _buildStatsSection()),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Container(
          decoration: _whiteBoxDecoration,
          padding: const EdgeInsets.all(16.0),
          child: _buildInfoSection(),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: _whiteBoxDecoration,
          padding: const EdgeInsets.all(16.0),
          child: _buildStatsSection(),
        ),
      ],
    );
  }

  Widget _buildInfoSection() {
    final String displayName = userData['displayName'] ?? '';
    final String username = userData['username'] ?? '';
    final String? photoUrl = userData['photoUrl'];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 45,
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
              child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person, size: 50) : null,
            ),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  ElevatedButton(
                    onPressed: onFollowToggle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFollowing ? Colors.grey[200] : Colors.white,
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black),
                    ),
                    child: Text(isFollowing ? "unfollow" : "follow"),
                  )
                else
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text("edit info"),
                  ),
                const SizedBox(height: 8),
                Text("${userData['followerCount'] ?? 0} followers", style: const TextStyle(fontSize: 12)),
                Text("${userData['followingCount'] ?? 0} following", style: const TextStyle(fontSize: 12)),
              ],
            )
          ],
        ),
        const SizedBox(height: 16),
        Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text('@$username', style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  Widget _buildStatsSection() {
    return const Center(child: Text("Social Links & Highlights"));
  }

  final BoxDecoration _whiteBoxDecoration = const BoxDecoration(
    color: Colors.white,
    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(1, 1))],
  );
}

class ProfileNavBar extends StatelessWidget {
  final List<String> tabTitles;
  final int currentIndex;
  final Function(int) onTabChanged;
  final bool canEdit;
  final VoidCallback onUploadImage;

  const ProfileNavBar({
    super.key,
    required this.tabTitles,
    required this.currentIndex,
    required this.onTabChanged,
    required this.canEdit,
    required this.onUploadImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(tabTitles.length, (i) {
              final isActive = currentIndex == i;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: GestureDetector(
                  onTap: () => onTabChanged(i),
                  child: Text(
                    tabTitles[i],
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      decoration: isActive ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}