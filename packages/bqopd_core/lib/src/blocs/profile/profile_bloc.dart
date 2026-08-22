import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../models/user_profile.dart';
import '../../interfaces/user_repository_interface.dart';
import '../../interfaces/engagement_repository_interface.dart';

/// Base class for all profile-related events.
abstract class ProfileEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

/// Event dispatched to request loading profile data for a specific user ID.
class LoadProfileRequested extends ProfileEvent {
  final String userId;
  final String currentAuthId;
  final bool isViewerAdmin;
  final bool isViewerModerator;
  final bool isViewerCurator;
  final String? initialTab;

  LoadProfileRequested({
    required this.userId,
    required this.currentAuthId,
    required this.isViewerAdmin,
    required this.isViewerModerator,
    required this.isViewerCurator,
    this.initialTab,
  });

  @override
  List<Object?> get props => [
    userId,
    currentAuthId,
    isViewerAdmin,
    isViewerModerator,
    isViewerCurator,
    initialTab,
  ];
}

/// Internal event fired when profile data stream updates.
class _ProfileDataUpdated extends ProfileEvent {
  final UserProfile profile;
  final String currentAuthId;
  final bool isViewerAdmin;
  final bool isViewerModerator;
  final bool isViewerCurator;
  final String? initialTab;

  _ProfileDataUpdated(
      this.profile,
      this.currentAuthId,
      this.isViewerAdmin,
      this.isViewerModerator,
      this.isViewerCurator,
      this.initialTab,
      );

  @override
  List<Object?> get props => [
    profile,
    currentAuthId,
    isViewerAdmin,
    isViewerModerator,
    isViewerCurator,
    initialTab,
  ];
}

/// Internal event fired when follow status updates.
class _FollowStatusUpdated extends ProfileEvent {
  final bool isFollowing;
  _FollowStatusUpdated(this.isFollowing);

  @override
  List<Object?> get props => [isFollowing];
}

/// Event dispatched when user selects a different main tab.
class ChangeTabRequested extends ProfileEvent {
  final int index;
  ChangeTabRequested(this.index);

  @override
  List<Object?> get props => [index];
}

/// Event dispatched to toggle follow/unfollow status for the current target profile.
class ToggleFollowRequested extends ProfileEvent {}

// RESTORED: Events for deletion required by the UI
class DeleteFolioRequested extends ProfileEvent {
  final String fanzineId;
  DeleteFolioRequested(this.fanzineId);

  @override
  List<Object?> get props => [fanzineId];
}

class DeleteImageRequested extends ProfileEvent {
  final String imageId;
  DeleteImageRequested(this.imageId);

  @override
  List<Object?> get props => [imageId];
}

/// State representing the current profile view configuration and data.
class ProfileState extends Equatable {
  final UserProfile? userData;
  final bool isLoading;
  final bool isFollowing;
  final int currentTabIndex;
  final List<String> visibleTabs;
  final String? errorMessage;

  const ProfileState({
    this.userData,
    this.isLoading = false,
    this.isFollowing = false,
    this.currentTabIndex = 0,
    this.visibleTabs = const [],
    this.errorMessage,
  });

  ProfileState copyWith({
    UserProfile? userData,
    bool? isLoading,
    bool? isFollowing,
    int? currentTabIndex,
    List<String>? visibleTabs,
    String? errorMessage,
  }) {
    return ProfileState(
      userData: userData ?? this.userData,
      isLoading: isLoading ?? this.isLoading,
      isFollowing: isFollowing ?? this.isFollowing,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
      visibleTabs: visibleTabs ?? this.visibleTabs,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    userData,
    isLoading,
    isFollowing,
    currentTabIndex,
    visibleTabs,
    errorMessage,
  ];
}

/// Business Logic Component managing profile state, tab navigation, and social follow interactions.
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final IUserRepository _userRepository;
  final IEngagementRepository _engagementRepository;

  StreamSubscription? _userSub;
  StreamSubscription? _followSub;

  ProfileBloc({
    required IUserRepository userRepository,
    required IEngagementRepository engagementRepository,
  })  : _userRepository = userRepository,
        _engagementRepository = engagementRepository,
        super(const ProfileState(isLoading: true)) {
    on<LoadProfileRequested>(_onLoadRequested);
    on<_ProfileDataUpdated>(_onProfileDataUpdated);
    on<_FollowStatusUpdated>(_onFollowStatusUpdated);
    on<ChangeTabRequested>(_onChangeTab);
    on<ToggleFollowRequested>(_onToggleFollow);
    // Note: Delete handlers are handled by repositories/cloud functions, restored for UI compilation
    on<DeleteFolioRequested>((event, emit) {});
    on<DeleteImageRequested>((event, emit) {});
  }

  Future<void> _onLoadRequested(
      LoadProfileRequested event, Emitter<ProfileState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    await _userSub?.cancel();
    await _followSub?.cancel();

    _followSub =
        _engagementRepository.isFollowing(event.userId).listen((following) {
          add(_FollowStatusUpdated(following));
        });

    _userSub = _userRepository.watchUser(event.userId).listen((profile) {
      if (profile != null) {
        add(_ProfileDataUpdated(
          profile,
          event.currentAuthId,
          event.isViewerAdmin,
          event.isViewerModerator,
          event.isViewerCurator,
          event.initialTab,
        ));
      }
    });
  }

  void _onProfileDataUpdated(
      _ProfileDataUpdated event, Emitter<ProfileState> emit) {
    final profile = event.profile;
    final bool isMe = event.currentAuthId == profile.uid;

    List<String> tabs = [];

    if (isMe) {
      tabs.add('settings');
    }

    final bool viewerHasAccess =
        event.isViewerCurator || event.isViewerModerator || event.isViewerAdmin;
    final bool ownerIsCurator = profile.isCurator;

    if (isMe && viewerHasAccess) {
      tabs.add('curator');
    } else if (!isMe && viewerHasAccess && ownerIsCurator) {
      tabs.add('curator');
    }

    tabs.add('maker');
    tabs.add('index');
    tabs.add('collection');

    int startTab = tabs.indexOf('maker');
    if (startTab == -1) startTab = 0;

    // Resolve currently selected tab name if a valid tab is already active
    final String? activeTabName = (!state.isLoading &&
        state.visibleTabs.isNotEmpty &&
        state.currentTabIndex < state.visibleTabs.length)
        ? state.visibleTabs[state.currentTabIndex]
        : null;

    if (activeTabName != null && tabs.contains(activeTabName)) {
      // Preserve active tab by name across stream updates
      startTab = tabs.indexOf(activeTabName);
    } else if (event.initialTab != null && tabs.contains(event.initialTab)) {
      // Honor initialTab on fresh load or explicit URL navigation
      startTab = tabs.indexOf(event.initialTab!);
    } else if (state.currentTabIndex >= 0 && state.currentTabIndex < tabs.length) {
      startTab = state.currentTabIndex;
    }

    emit(state.copyWith(
      userData: profile,
      visibleTabs: tabs,
      currentTabIndex: startTab,
      isLoading: false,
    ));
  }

  void _onFollowStatusUpdated(
      _FollowStatusUpdated event, Emitter<ProfileState> emit) {
    emit(state.copyWith(isFollowing: event.isFollowing));
  }

  void _onChangeTab(ChangeTabRequested event, Emitter<ProfileState> emit) {
    emit(state.copyWith(currentTabIndex: event.index));
  }

  Future<void> _onToggleFollow(
      ToggleFollowRequested event, Emitter<ProfileState> emit) async {
    final uid = state.userData?.uid;
    if (uid == null) return;
    try {
      await _engagementRepository.setFollowStatus(uid, !state.isFollowing);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() {
    _userSub?.cancel();
    _followSub?.cancel();
    return super.close();
  }
}