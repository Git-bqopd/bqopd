import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
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
  final bool isViewerEditor;
  LoadProfileRequested({required this.userId, required this.currentAuthId, required this.isViewerEditor});
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
    on<ChangeTabRequested>(_onChangeTab);
    on<ToggleFollowRequested>(_onToggleFollow);
  }

  Future<void> _onLoadRequested(LoadProfileRequested event, Emitter<ProfileState> emit) async {
    await _userSub?.cancel();
    await _followSub?.cancel();

    _followSub = _engagementRepository.isFollowing(event.userId).listen((following) {
      add(LoadProfileRequested(userId: event.userId, currentAuthId: event.currentAuthId, isViewerEditor: event.isViewerEditor)); // Refresh local state via re-emission check
      emit(state.copyWith(isFollowing: following));
    });

    _userSub = _userRepository.watchUser(event.userId).listen((doc) {
      if (!doc.exists) {
        emit(state.copyWith(isLoading: false, errorMessage: "User not found"));
        return;
      }

      final userData = doc.data() as Map<String, dynamic>;
      final bool isMe = event.currentAuthId == event.userId;
      final bool isTargetEditor = userData['Editor'] == true || userData['isEditor'] == true;

      // Determine visible tabs
      List<String> tabs = [];
      if (isMe || (isTargetEditor && event.isViewerEditor)) {
        tabs.add('editor');
      }
      tabs.addAll(['pages', 'works', 'comments', 'mentions', 'collection']);

      emit(state.copyWith(
        userData: userData,
        visibleTabs: tabs,
        isLoading: false,
      ));
    });
  }

  void _onChangeTab(ChangeTabRequested event, Emitter<ProfileState> emit) {
    emit(state.copyWith(currentTabIndex: event.index));
  }

  Future<void> _onToggleFollow(ToggleFollowRequested event, Emitter<ProfileState> emit) async {
    final uid = state.userData?['uid'];
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