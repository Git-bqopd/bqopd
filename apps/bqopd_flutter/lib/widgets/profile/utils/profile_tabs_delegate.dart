import 'package:flutter/material.dart';

class ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  ProfileTabsDelegate({required this.child});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      elevation: overlapsContent ? 4 : 0,
      child: child,
    );
  }

  @override
  double get maxExtent => 50.0;

  @override
  double get minExtent => 50.0;

  @override
  bool shouldRebuild(covariant ProfileTabsDelegate oldDelegate) => true;
}