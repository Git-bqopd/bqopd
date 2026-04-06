import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/fanzine_repository.dart';
import '../../repositories/pipeline_repository.dart';
import '../../services/username_service.dart';

// --- EVENTS ---

abstract class CuratorWorkbenchEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadWorkbenchRequested extends CuratorWorkbenchEvent {
  final String fanzineId;
  LoadWorkbenchRequested(this.fanzineId);
}

class ChangePageRequested extends CuratorWorkbenchEvent {
  final int index;
  ChangePageRequested(this.index);
}

class SaveCurrentPageRequested extends CuratorWorkbenchEvent {
  final String text;
  SaveCurrentPageRequested(this.text);
}

class AnalyzeEntitiesRequested extends CuratorWorkbenchEvent {
  final String text;
  AnalyzeEntitiesRequested(this.text);
}

class TriggerOcrRequested extends CuratorWorkbenchEvent {}
class TriggerFinalizeRequested extends CuratorWorkbenchEvent {}
class SoftPublishWorkbenchRequested extends CuratorWorkbenchEvent {}

// --- STATE ---

class CuratorWorkbenchState extends Equatable {
  final List<DocumentSnapshot> pages;
  final int currentIndex;
  final String pipelineStatus;
  final List<Map<String, dynamic>> detectedEntities;
  final bool isLoading;
  final bool isSaving;
  final bool isValidatingEntities;
  final String? errorMessage;

  const CuratorWorkbenchState({
    this.pages = const [],
    this.currentIndex = 0,
    this.pipelineStatus = 'idle',
    this.detectedEntities = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.isValidatingEntities = false,
    this.errorMessage,
  });

  CuratorWorkbenchState copyWith({
    List<DocumentSnapshot>? pages,
    int? currentIndex,
    String? pipelineStatus,
    List<Map<String, dynamic>>? detectedEntities,
    bool? isLoading,
    bool? isSaving,
    bool? isValidatingEntities,
    String? errorMessage,
  }) {
    return CuratorWorkbenchState(
      pages: pages ?? this.pages,
      currentIndex: currentIndex ?? this.currentIndex,
      pipelineStatus: pipelineStatus ?? this.pipelineStatus,
      detectedEntities: detectedEntities ?? this.detectedEntities,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isValidatingEntities: isValidatingEntities ?? this.isValidatingEntities,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [pages, currentIndex, pipelineStatus, detectedEntities, isLoading, isSaving, isValidatingEntities, errorMessage];
}

// --- BLOC ---

class CuratorWorkbenchBloc extends Bloc<CuratorWorkbenchEvent, CuratorWorkbenchState> {
  final FanzineRepository _fanzineRepository;
  final PipelineRepository _pipelineRepository;
  final String fanzineId;

  StreamSubscription? _pagesSub;
  StreamSubscription? _fzSub;

  CuratorWorkbenchBloc({
    required FanzineRepository fanzineRepository,
    required PipelineRepository pipelineRepository,
    required this.fanzineId,
  }) : _fanzineRepository = fanzineRepository,
        _pipelineRepository = pipelineRepository,
        super(const CuratorWorkbenchState(isLoading: true)) {
    on<LoadWorkbenchRequested>(_onLoadRequested);
    on<ChangePageRequested>(_onChangePage);
    on<SaveCurrentPageRequested>(_onSavePage);
    on<AnalyzeEntitiesRequested>(_onAnalyzeEntities);
    on<TriggerOcrRequested>(_onTriggerOcr);
    on<TriggerFinalizeRequested>(_onTriggerFinalize);
    on<SoftPublishWorkbenchRequested>(_onSoftPublish);
  }

  Future<void> _onLoadRequested(LoadWorkbenchRequested event, Emitter<CuratorWorkbenchState> emit) async {
    await _pagesSub?.cancel();
    await _fzSub?.cancel();

    _fzSub = _fanzineRepository.watchFanzine(fanzineId).listen((doc) {
      if (doc.exists) {
        add(AnalyzeEntitiesRequested('')); // Initial trigger or refresh logic
        emit(state.copyWith(pipelineStatus: doc.get('processingStatus') ?? 'idle'));
      }
    });

    _pagesSub = _fanzineRepository.watchPages(fanzineId).listen((snapshot) {
      emit(state.copyWith(pages: snapshot.docs, isLoading: false));
    });
  }

  void _onChangePage(ChangePageRequested event, Emitter<CuratorWorkbenchState> emit) {
    if (event.index >= 0 && event.index < state.pages.length) {
      emit(state.copyWith(currentIndex: event.index));
    }
  }

  Future<void> _onSavePage(SaveCurrentPageRequested event, Emitter<CuratorWorkbenchState> emit) async {
    if (state.pages.isEmpty) return;
    emit(state.copyWith(isSaving: true));
    try {
      final pageId = state.pages[state.currentIndex].id;
      await _fanzineRepository.updatePageText(fanzineId, pageId, event.text);
      emit(state.copyWith(isSaving: false));
    } catch (e) {
      emit(state.copyWith(isSaving: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onAnalyzeEntities(AnalyzeEntitiesRequested event, Emitter<CuratorWorkbenchState> emit) async {
    if (event.text.isEmpty) return;
    emit(state.copyWith(isValidatingEntities: true));

    final regex = RegExp(r'\[\[(.*?)(?:\|(.*?))?\]\]');
    final matches = regex.allMatches(event.text);
    final List<Map<String, dynamic>> results = [];
    final Set<String> processed = {};

    for (final match in matches) {
      final String rawName = match.group(1) ?? '';
      if (rawName.isEmpty || processed.contains(rawName)) continue;
      processed.add(rawName);

      final String handle = normalizeHandle(rawName);
      final data = await _fanzineRepository.checkHandleStatus(handle);

      String status = 'missing';
      String? targetId;
      String? redirect;

      if (data != null) {
        if (data.containsKey('redirect')) {
          status = 'alias';
          redirect = data['redirect'];
        } else {
          status = 'exists';
          targetId = data['uid'];
        }
      }

      results.add({ 'name': rawName, 'handle': handle, 'status': status, 'targetId': targetId, 'redirect': redirect });
    }

    emit(state.copyWith(detectedEntities: results, isValidatingEntities: false));
  }

  Future<void> _onTriggerOcr(TriggerOcrRequested event, Emitter<CuratorWorkbenchState> emit) async {
    try {
      await _pipelineRepository.triggerBatchOcr(fanzineId);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onTriggerFinalize(TriggerFinalizeRequested event, Emitter<CuratorWorkbenchState> emit) async {
    try {
      await _pipelineRepository.finalizeFanzineData(fanzineId);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onSoftPublish(SoftPublishWorkbenchRequested event, Emitter<CuratorWorkbenchState> emit) async {
    emit(state.copyWith(isSaving: true));
    try {
      await _fanzineRepository.softPublish(fanzineId);
      emit(state.copyWith(isSaving: false));
    } catch (e) {
      emit(state.copyWith(isSaving: false, errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() {
    _pagesSub?.cancel();
    _fzSub?.cancel();
    return super.close();
  }
}