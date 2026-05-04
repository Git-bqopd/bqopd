import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/user_repository.dart';
import '../../services/location_service.dart';
import '../../services/username_service.dart';

// --- EVENTS ---

abstract class EditInfoEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadEditInfoRequested extends EditInfoEvent {
  final String targetUid;
  LoadEditInfoRequested(this.targetUid);

  @override
  List<Object?> get props => [targetUid];
}

class FetchAddressDetailsRequested extends EditInfoEvent {
  final String placeId;
  FetchAddressDetailsRequested(this.placeId);

  @override
  List<Object?> get props => [placeId];
}

class SaveProfileRequested extends EditInfoEvent {
  final String uid;
  final String displayName;
  final String userName;
  final String email;
  final String bio;
  final String street1;
  final String street2;
  final String city;
  final String state;
  final String zipCode;
  final String country;
  final String firstName;
  final String lastName;
  final String xHandle;
  final String instagramHandle;
  final String githubHandle;
  final String? profilePhotoUrl;
  final String initialUsername;

  SaveProfileRequested({
    required this.uid,
    required this.displayName,
    required this.userName,
    required this.email,
    required this.bio,
    required this.street1,
    required this.street2,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.country,
    required this.firstName,
    required this.lastName,
    required this.xHandle,
    required this.instagramHandle,
    required this.githubHandle,
    this.profilePhotoUrl,
    required this.initialUsername,
  });

  @override
  List<Object?> get props => [uid, displayName, userName, email, bio, street1, street2, city, state, zipCode, country, firstName, lastName, xHandle, instagramHandle, githubHandle, profilePhotoUrl, initialUsername];
}

// --- STATE ---

enum EditInfoStatus { initial, loading, loaded, saving, success, failure, addressLoading, addressLoaded }

class EditInfoState extends Equatable {
  final EditInfoStatus status;
  final Map<String, dynamic> userData;
  final Map<String, dynamic> profileData;
  final Map<String, String>? addressData;
  final String initialUsername;
  final String? errorMessage;

  const EditInfoState({
    this.status = EditInfoStatus.initial,
    this.userData = const {},
    this.profileData = const {},
    this.addressData,
    this.initialUsername = '',
    this.errorMessage,
  });

  EditInfoState copyWith({
    EditInfoStatus? status,
    Map<String, dynamic>? userData,
    Map<String, dynamic>? profileData,
    Map<String, String>? addressData,
    String? initialUsername,
    String? errorMessage,
  }) {
    return EditInfoState(
      status: status ?? this.status,
      userData: userData ?? this.userData,
      profileData: profileData ?? this.profileData,
      addressData: addressData ?? this.addressData,
      initialUsername: initialUsername ?? this.initialUsername,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, userData, profileData, addressData, initialUsername, errorMessage];
}

// --- BLOC ---

class EditInfoBloc extends Bloc<EditInfoEvent, EditInfoState> {
  final UserRepository _userRepository;
  final LocationService _locationService;

  EditInfoBloc({
    required UserRepository userRepository,
    required LocationService locationService,
  })  : _userRepository = userRepository,
        _locationService = locationService,
        super(const EditInfoState()) {
    on<LoadEditInfoRequested>(_onLoadRequested);
    on<FetchAddressDetailsRequested>(_onFetchAddress);
    on<SaveProfileRequested>(_onSaveProfile);
  }

  Future<void> _onLoadRequested(LoadEditInfoRequested event, Emitter<EditInfoState> emit) async {
    emit(state.copyWith(status: EditInfoStatus.loading));

    if (event.targetUid.isEmpty) {
      emit(state.copyWith(status: EditInfoStatus.failure, errorMessage: "User ID is empty."));
      return;
    }

    try {
      final data = await _userRepository.fetchFullUserProfile(event.targetUid);

      final profileData = data['profile'] as Map<String, dynamic>? ?? {};
      final initialUsername = profileData['username'] ?? '';

      emit(state.copyWith(
        status: EditInfoStatus.loaded,
        userData: data['user'] as Map<String, dynamic>? ?? {},
        profileData: profileData,
        initialUsername: initialUsername,
      ));
    } catch (e) {
      emit(state.copyWith(status: EditInfoStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onFetchAddress(FetchAddressDetailsRequested event, Emitter<EditInfoState> emit) async {
    emit(state.copyWith(status: EditInfoStatus.addressLoading));

    try {
      final addressData = await _locationService.getPlaceDetails(event.placeId);
      if (addressData != null) {
        emit(state.copyWith(status: EditInfoStatus.addressLoaded, addressData: addressData));
      } else {
        emit(state.copyWith(status: EditInfoStatus.failure, errorMessage: "Could not fetch address details."));
      }
    } catch (e) {
      emit(state.copyWith(status: EditInfoStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onSaveProfile(SaveProfileRequested event, Emitter<EditInfoState> emit) async {
    emit(state.copyWith(status: EditInfoStatus.saving));

    try {
      final finalUsername = normalizeHandle(event.userName);

      final publicData = {
        'username': finalUsername,
        'displayName': event.displayName.trim(),
        'bio': event.bio.trim(),
        'photoUrl': event.profilePhotoUrl,
        'xHandle': event.xHandle.trim().replaceAll('@', ''),
        'instagramHandle': event.instagramHandle.trim().replaceAll('@', ''),
        'githubHandle': event.githubHandle.trim().replaceAll('@', ''),
        'updatedAt': FieldValue.serverTimestamp(),
        'uid': event.uid,
      };

      final privateData = {
        'firstName': event.firstName.trim(),
        'lastName': event.lastName.trim(),
        'street1': event.street1.trim(),
        'street2': event.street2.trim(),
        'city': event.city.trim(),
        'state': event.state.trim(),
        'zipCode': event.zipCode.trim(),
        'country': event.country.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'uid': event.uid,
      };

      await _userRepository.saveFullUserProfile(
        uid: event.uid,
        publicData: publicData,
        privateData: privateData,
        initialUsername: event.initialUsername,
        finalUsername: finalUsername,
      );

      // Re-emit loaded to reflect new initial state
      emit(state.copyWith(
        status: EditInfoStatus.success,
        initialUsername: finalUsername,
      ));
    } catch (e) {
      emit(state.copyWith(status: EditInfoStatus.failure, errorMessage: e.toString()));
    }
  }
}