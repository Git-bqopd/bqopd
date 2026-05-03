import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- EVENTS ---
abstract class FanzineReaderEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class InitializeReaderRequested extends FanzineReaderEvent {
  final String? fanzineId;
  final String? shortCode;
  final String? currentUserId;
  final bool isInternalStaff; // Admin, Mod, or Curator

  InitializeReaderRequested({
    this.fanzineId,
    this.shortCode,
    this.currentUserId,
    required this.isInternalStaff,
  });

  @override
  List<Object?> get props => [fanzineId, shortCode, currentUserId, isInternalStaff];
}

class _FanzineDataUpdated extends FanzineReaderEvent {
  final Map<String, dynamic> data;
  final String fanzineId;
  _FanzineDataUpdated(this.data, this.fanzineId);
}

class _PagesDataUpdated extends FanzineReaderEvent {
  final List<Map<String, dynamic>> pages;
  _PagesDataUpdated(this.pages);
}

class _AccessDenied extends FanzineReaderEvent {}

// --- STATE ---
class FanzineReaderState extends Equatable {
  final bool isLoading;
  final bool isAccessDenied;
  final String? resolvedFanzineId;
  final String? resolvedShortCode;
  final String? resolvedType;
  final String fanzineTitle;
  final bool twoPagePreference;
  final bool hasCover;
  final List<Map<String, dynamic>> pages;
  final String? errorMessage;

  const FanzineReaderState({
    this.isLoading = true,
    this.isAccessDenied = false,
    this.resolvedFanzineId,
    this.resolvedShortCode,
    this.resolvedType,
    this.fanzineTitle = 'Untitled',
    this.twoPagePreference = true,
    this.hasCover = true,
    this.pages = const [],
    this.errorMessage,
  });

  FanzineReaderState copyWith({
    bool? isLoading,
    bool? isAccessDenied,
    String? resolvedFanzineId,
    String? resolvedShortCode,
    String? resolvedType,
    String? fanzineTitle,
    bool? twoPagePreference,
    bool? hasCover,
    List<Map<String, dynamic>>? pages,
    String? errorMessage,
  }) {
    return FanzineReaderState(
      isLoading: isLoading ?? this.isLoading,
      isAccessDenied: isAccessDenied ?? this.isAccessDenied,
      resolvedFanzineId: resolvedFanzineId ?? this.resolvedFanzineId,
      resolvedShortCode: resolvedShortCode ?? this.resolvedShortCode,
      resolvedType: resolvedType ?? this.resolvedType,
      fanzineTitle: fanzineTitle ?? this.fanzineTitle,
      twoPagePreference: twoPagePreference ?? this.twoPagePreference,
      hasCover: hasCover ?? this.hasCover,
      pages: pages ?? this.pages,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    isLoading, isAccessDenied, resolvedFanzineId, resolvedShortCode,
    resolvedType, fanzineTitle, twoPagePreference, hasCover, pages, errorMessage
  ];
}

// --- BLOC ---
class FanzineReaderBloc extends Bloc<FanzineReaderEvent, FanzineReaderState> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription? _fanzineSub;
  StreamSubscription? _pagesSub;

  String? _currentUserId;
  bool _isInternalStaff = false;

  FanzineReaderBloc() : super(const FanzineReaderState()) {
    on<InitializeReaderRequested>(_onInitializeReader);
    on<_FanzineDataUpdated>(_onFanzineDataUpdated);
    on<_PagesDataUpdated>(_onPagesDataUpdated);
    on<_AccessDenied>((event, emit) => emit(state.copyWith(isAccessDenied: true, isLoading: false)));
  }

  Future<void> _onInitializeReader(InitializeReaderRequested event, Emitter<FanzineReaderState> emit) async {
    emit(state.copyWith(isLoading: true, isAccessDenied: false, errorMessage: null));

    _currentUserId = event.currentUserId;
    _isInternalStaff = event.isInternalStaff;

    String? targetId = event.fanzineId;
    String? targetShortCode = event.shortCode;

    try {
      // 1. Resolve Fallback Shortcodes (Login/Register App Defaults)
      if (targetShortCode == null && targetId == null) {
        if (_currentUserId != null) {
          final userDoc = await _db.collection('Users').doc(_currentUserId).get();
          if (userDoc.exists) targetShortCode = userDoc.data()?['newFanzine'];
        }
        if (targetShortCode == null) {
          final settings = await _db.collection('app_settings').doc('main_settings').get();
          if (settings.exists) targetShortCode = settings.data()?['login_zine_shortcode'];
        }
      }

      // 2. Resolve ShortCode to Document ID
      if (targetId == null && targetShortCode != null) {
        final fanzineQuery = await _db.collection('fanzines')
            .where('shortCode', isEqualTo: targetShortCode)
            .limit(1)
            .get();

        if (fanzineQuery.docs.isNotEmpty) {
          targetId = fanzineQuery.docs.first.id;
        } else {
          final scDoc = await _db.collection('shortcodes').doc(targetShortCode.toUpperCase()).get();
          if (scDoc.exists && scDoc.data()?['type'] == 'fanzine') {
            targetId = scDoc.data()?['contentId'];
          }
        }
      }

      if (targetId == null) {
        emit(state.copyWith(isLoading: false));
        return;
      }

      emit(state.copyWith(resolvedFanzineId: targetId, resolvedShortCode: targetShortCode));
      _setupListeners(targetId);

    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _setupListeners(String fanzineId) {
    _fanzineSub?.cancel();
    _fanzineSub = _db.collection('fanzines').doc(fanzineId).snapshots().listen((doc) {
      if (!doc.exists) return;
      add(_FanzineDataUpdated(doc.data() as Map<String, dynamic>, doc.id));
    });

    _pagesSub?.cancel();
    _pagesSub = _db.collection('fanzines').doc(fanzineId)
        .collection('pages')
        .orderBy('pageNumber')
        .snapshots().listen((snapshot) {
      final pages = snapshot.docs.map((d) {
        final data = d.data();
        data['__id'] = d.id;
        return data;
      }).toList();
      add(_PagesDataUpdated(pages));
    });
  }

  void _onFanzineDataUpdated(_FanzineDataUpdated event, Emitter<FanzineReaderState> emit) {
    final data = event.data;

    // SECURITY CHECK: isLive logic for Public vs Staff
    final bool isLive = data['isLive'] ?? false;
    final String ownerId = data['ownerId'] ?? data['editorId'] ?? '';
    final List<String> editors = List<String>.from(data['editors'] ?? []);

    final bool isAuthorizedCreator = _currentUserId != null && (_currentUserId == ownerId || editors.contains(_currentUserId));
    final bool hasPermission = isLive || _isInternalStaff || isAuthorizedCreator;

    if (!hasPermission) {
      add(_AccessDenied());
      return;
    }

    emit(state.copyWith(
      isAccessDenied: false,
      resolvedType: data['type'] ?? 'fanzine',
      fanzineTitle: data['title'] ?? 'Untitled',
      twoPagePreference: data['twoPage'] ?? true,
      hasCover: data['hasCover'] ?? true,
    ));

    _checkIfFullyLoaded(emit);
  }

  void _onPagesDataUpdated(_PagesDataUpdated event, Emitter<FanzineReaderState> emit) {
    emit(state.copyWith(pages: event.pages));
    _checkIfFullyLoaded(emit);
  }

  void _checkIfFullyLoaded(Emitter<FanzineReaderState> emit) {
    // Only drop the loading flag once we have data and aren't denied
    if (!state.isAccessDenied && state.resolvedType != null) {
      emit(state.copyWith(isLoading: false));
    }
  }

  @override
  Future<void> close() {
    _fanzineSub?.cancel();
    _pagesSub?.cancel();
    return super.close();
  }
}