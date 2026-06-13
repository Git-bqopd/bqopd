import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../models/user_profile.dart';
import '../../interfaces/user_repository_interface.dart';
import '../../interfaces/engagement_repository_interface.dart';

abstract class ProfileEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

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
}

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
}

class _FollowStatusUpdated extends ProfileEvent {
  final bool isFollowing;
  _FollowStatusUpdated(this.isFollowing);
}

class ChangeTabRequested extends ProfileEvent {
  final int index;
  ChangeTabRequested(this.index);
}

class ToggleFollowRequested extends ProfileEvent {}

// RESTORED: Events for deletion required by the UI
class DeleteFolioRequested extends ProfileEvent {
  final String fanzineId;
  DeleteFolioRequested(this.fanzineId);
}

class DeleteImageRequested extends ProfileEvent {
  final String imageId;
  DeleteImageRequested(this.imageId);
}

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
  List<Object?> get props => [userData, isLoading, isFollowing, currentTabIndex, visibleTabs, errorMessage];
}

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
    // Note: Delete handlers are omitted here because they require direct Firestore/Storage access
    // which should be handled by the Repository implementation or specialized Cloud Functions.
    // For now, these events are restored to allow UI compilation.
    on<DeleteFolioRequested>((event, emit) {});
    on<DeleteImageRequested>((event, emit) {});
  }

  Future<void> _onLoadRequested(LoadProfileRequested event, Emitter<ProfileState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    await _userSub?.cancel();
    await _followSub?.cancel();

    _followSub = _engagementRepository.isFollowing(event.userId).listen((following) {
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

  void _onProfileDataUpdated(_ProfileDataUpdated event, Emitter<ProfileState> emit) {
    final profile = event.profile;
    final bool isMe = event.currentAuthId == profile.uid;

    List<String> tabs = [];

    if (isMe) {
      tabs.add('settings');
    }

    final bool viewerHasAccess = event.isViewerCurator || event.isViewerModerator || event.isViewerAdmin;
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

    if (event.initialTab != null && tabs.contains(event.initialTab)) {
      startTab = tabs.indexOf(event.initialTab!);
    } else if (state.userData != null && state.currentTabIndex < tabs.length) {
      // FIX: If we already have user data loaded in the previous state, we preserve the active
      // currentTabIndex exactly as-is, preventing index-0 (settings) from reverting to maker.
      startTab = state.currentTabIndex;
    }

    emit(state.copyWith(
      userData: profile,
      visibleTabs: tabs,
      currentTabIndex: startTab,
      isLoading: false,
    ));
  }

  void _onFollowStatusUpdated(_FollowStatusUpdated event, Emitter<ProfileState> emit) {
    emit(state.copyWith(isFollowing: event.isFollowing));
  }

  void _onChangeTab(ChangeTabRequested event, Emitter<ProfileState> emit) {
    emit(state.copyWith(currentTabIndex: event.index));
  }

  Future<void> _onToggleFollow(ToggleFollowRequested event, Emitter<ProfileState> emit) async {
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