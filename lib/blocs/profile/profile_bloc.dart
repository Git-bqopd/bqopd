import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/user_repository.dart';
import '../../repositories/engagement_repository.dart';

// --- EVENTS ---
abstract class ProfileEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadProfileRequested extends ProfileEvent {
  final String userId;
  final String currentAuthId;
  final bool isViewerModerator;
  final bool isViewerCurator;
  final String? initialTab;

  LoadProfileRequested({
    required this.userId,
    required this.currentAuthId,
    required this.isViewerModerator,
    required this.isViewerCurator,
    this.initialTab,
  });
}

class _ProfileDataUpdated extends ProfileEvent {
  final DocumentSnapshot doc;
  final String currentAuthId;
  final bool isViewerModerator;
  final bool isViewerCurator;
  final String? initialTab;

  _ProfileDataUpdated(this.doc, this.currentAuthId, this.isViewerModerator, this.isViewerCurator, this.initialTab);
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

// --- STATE ---
class ProfileState extends Equatable {
  final Map<String, dynamic>? userData;
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
    Map<String, dynamic>? userData,
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

// --- BLOC ---
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final UserRepository _userRepository;
  final EngagementRepository _engagementRepository;

  StreamSubscription? _userSub;
  StreamSubscription? _followSub;

  ProfileBloc({
    required UserRepository userRepository,
    required EngagementRepository engagementRepository,
  }) : _userRepository = userRepository,
        _engagementRepository = engagementRepository,
        super(const ProfileState(isLoading: true)) {
    on<LoadProfileRequested>(_onLoadRequested);
    on<_ProfileDataUpdated>(_onProfileDataUpdated);
    on<_FollowStatusUpdated>(_onFollowStatusUpdated);
    on<ChangeTabRequested>(_onChangeTab);
    on<ToggleFollowRequested>(_onToggleFollow);
  }

  Future<void> _onLoadRequested(LoadProfileRequested event, Emitter<ProfileState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    await _userSub?.cancel();
    await _followSub?.cancel();

    _followSub = _engagementRepository.isFollowing(event.userId).listen((following) {
      add(_FollowStatusUpdated(following));
    });

    _userSub = _userRepository.watchUser(event.userId).listen((doc) {
      add(_ProfileDataUpdated(doc, event.currentAuthId, event.isViewerModerator, event.isViewerCurator, event.initialTab));
    });
  }

  void _onProfileDataUpdated(_ProfileDataUpdated event, Emitter<ProfileState> emit) {
    if (!event.doc.exists) {
      emit(state.copyWith(isLoading: false, errorMessage: "User not found"));
      return;
    }

    final userData = event.doc.data() as Map<String, dynamic>;
    final bool isMe = event.currentAuthId == event.doc.id;

    // Determine visible tabs in the requested order:
    // settings -> curator -> maker -> index -> collection
    List<String> tabs = [];

    // 1. Settings (Conditional)
    if (isMe || event.isViewerModerator) {
      tabs.add('settings');
    }

    // 2. Curator (Conditional)
    if (isMe || event.isViewerCurator || event.isViewerModerator) {
      tabs.add('curator');
    }

    // 3. Maker
    tabs.add('maker');

    // 4. Index
    tabs.add('index');

    // 5. Collection
    tabs.add('collection');

    int startTab = state.currentTabIndex;
    if (event.initialTab != null && tabs.contains(event.initialTab)) {
      startTab = tabs.indexOf(event.initialTab!);
    } else if (startTab >= tabs.length) {
      startTab = 0;
    }

    emit(state.copyWith(
      userData: userData,
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
    final uid = state.userData?['uid'];
    if (uid == null) {
      return;
    }
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