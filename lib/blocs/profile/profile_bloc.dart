import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/user_repository.dart';
import '../../repositories/engagement_repository.dart';
import '../../models/user_profile.dart';

// --- EVENTS ---
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
    required this.currentAuthId,    required this.isViewerAdmin,
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

  _ProfileDataUpdated(this.profile, this.currentAuthId, this.isViewerAdmin, this.isViewerModerator, this.isViewerCurator, this.initialTab);
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

class DeleteFolioRequested extends ProfileEvent {
  final String fanzineId;
  DeleteFolioRequested(this.fanzineId);
}

// --- STATE ---
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
    on<DeleteFolioRequested>(_onDeleteFolio);
  }

  Future<void> _onLoadRequested(LoadProfileRequested event, Emitter<ProfileState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    await _userSub?.cancel();
    await _followSub?.cancel();

    _followSub = _engagementRepository.isFollowing(event.userId).listen((following) {
      add(_FollowStatusUpdated(following));
    });

    _userSub = _userRepository.watchUser(event.userId).listen((doc) {
      if (doc.exists) {
        add(_ProfileDataUpdated(
            UserProfile.fromFirestore(doc),
            event.currentAuthId,
            event.isViewerAdmin,
            event.isViewerModerator,
            event.isViewerCurator,
            event.initialTab
        ));
      }
    });
  }

  void _onProfileDataUpdated(_ProfileDataUpdated event, Emitter<ProfileState> emit) {
    final profile = event.profile;
    final bool isMe = event.currentAuthId == profile.uid;

    List<String> tabs = [];

    // Settings tab is visible ONLY if it's my own profile AND I am an admin
    if (isMe && event.isViewerAdmin) {
      tabs.add('settings');
    }

    // Curator tab visibility logic
    final bool viewerHasAccess = event.isViewerCurator || event.isViewerModerator;
    final bool ownerIsCurator = profile.isCurator;

    if (isMe && viewerHasAccess) {
      tabs.add('curator');
    } else if (!isMe && viewerHasAccess && ownerIsCurator) {
      tabs.add('curator');
    }

    tabs.add('maker');
    tabs.add('index');
    tabs.add('collection');

    // DEFAULT LOGIC: Use the initialTab if provided (e.g., from deep link or saving a folio).
    // If no instruction is provided, default to the 'maker' tab.
    int startTab = tabs.indexOf('maker');
    if (startTab == -1) startTab = 0; // Fallback if maker isn't present

    if (event.initialTab != null && tabs.contains(event.initialTab)) {
      startTab = tabs.indexOf(event.initialTab!);
    } else if (state.currentTabIndex < tabs.length && state.currentTabIndex != 0) {
      // Maintain current index if we are already in a flow, unless we are resetting
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

  Future<void> _onDeleteFolio(DeleteFolioRequested event, Emitter<ProfileState> emit) async {
    final db = FirebaseFirestore.instance;
    final fzId = event.fanzineId;

    try {
      // 1. Get all pages in the folio
      final pagesSnap = await db.collection('fanzines').doc(fzId).collection('pages').get();
      final batch = db.batch();

      for (var pageDoc in pagesSnap.docs) {
        final pageData = pageDoc.data();
        final String? imageId = pageData['imageId'];

        if (imageId != null) {
          final imgDoc = await db.collection('images').doc(imageId).get();
          if (imgDoc.exists) {
            final imgData = imgDoc.data()!;
            final String? folioContext = imgData['folioContext'];

            // 2. Logic: If folioContext matches this fanzineId, it's a "Direct Upload" and should be deleted.
            // If it's null or different, it's an "Orphan" or borrowed from elsewhere and should be preserved.
            if (folioContext == fzId) {
              batch.delete(imgDoc.reference);
            } else {
              // Preserve Orphan: Just remove this folio from its usage list
              batch.update(imgDoc.reference, {
                'usedInFanzines': FieldValue.arrayRemove([fzId])
              });
            }
          }
        }
        // Always delete the page reference itself
        batch.delete(pageDoc.reference);
      }

      // 3. Delete the folio document
      batch.delete(db.collection('fanzines').doc(fzId));

      await batch.commit();
    } catch (e) {
      emit(state.copyWith(errorMessage: "Delete failed: ${e.toString()}"));
    }
  }

  @override
  Future<void> close() {
    _userSub?.cancel();
    _followSub?.cancel();
    return super.close();
  }
}