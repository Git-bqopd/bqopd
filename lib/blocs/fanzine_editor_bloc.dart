import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/fanzine_repository.dart';

// --- EVENTS ---

abstract class FanzineEditorEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadFanzineRequested extends FanzineEditorEvent {
  final String fanzineId;
  LoadFanzineRequested(this.fanzineId);
  @override
  List<Object?> get props => [fanzineId];
}

class UpdateFanzineTitle extends FanzineEditorEvent {
  final String title;
  UpdateFanzineTitle(this.title);
  @override
  List<Object?> get props => [title];
}

class AddPageRequested extends FanzineEditorEvent {
  final String shortcode;
  AddPageRequested(this.shortcode);
  @override
  List<Object?> get props => [shortcode];
}

class ReorderPageRequested extends FanzineEditorEvent {
  final DocumentSnapshot pageDoc;
  final int delta;
  final List<DocumentSnapshot> allPages;
  ReorderPageRequested(this.pageDoc, this.delta, this.allPages);
}

class ToggleLiveStatusRequested extends FanzineEditorEvent {
  final String currentStatus;
  ToggleLiveStatusRequested(this.currentStatus);
}

class SoftPublishRequested extends FanzineEditorEvent {}

// --- STATE ---

abstract class FanzineEditorState extends Equatable {
  @override
  List<Object?> get props => [];
}

class FanzineEditorInitial extends FanzineEditorState {}

class FanzineEditorLoading extends FanzineEditorState {}

class FanzineEditorLoaded extends FanzineEditorState {
  final Map<String, dynamic> fanzineData;
  final List<DocumentSnapshot> pages;
  final bool isProcessing; // For local UI loading overlay during saves

  FanzineEditorLoaded({
    required this.fanzineData,
    required this.pages,
    this.isProcessing = false
  });

  FanzineEditorLoaded copyWith({
    Map<String, dynamic>? fanzineData,
    List<DocumentSnapshot>? pages,
    bool? isProcessing,
  }) {
    return FanzineEditorLoaded(
      fanzineData: fanzineData ?? this.fanzineData,
      pages: pages ?? this.pages,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  @override
  List<Object?> get props => [fanzineData, pages, isProcessing];
}

class FanzineEditorFailure extends FanzineEditorState {
  final String message;
  FanzineEditorFailure(this.message);
  @override
  List<Object?> get props => [message];
}

// --- BLOC ---

class FanzineEditorBloc extends Bloc<FanzineEditorEvent, FanzineEditorState> {
  final FanzineRepository _repository;
  final String fanzineId;

  StreamSubscription? _fanzineSub;
  StreamSubscription? _pagesSub;

  FanzineEditorBloc({required FanzineRepository repository, required this.fanzineId})
      : _repository = repository,
        super(FanzineEditorInitial()) {
    on<LoadFanzineRequested>(_onLoadRequested);
    on<UpdateFanzineTitle>(_onUpdateTitle);
    on<AddPageRequested>(_onAddPage);
    on<ReorderPageRequested>(_onReorderPage);
    on<ToggleLiveStatusRequested>(_onToggleStatus);
    on<SoftPublishRequested>(_onSoftPublish);
  }

  Future<void> _onLoadRequested(LoadFanzineRequested event, Emitter<FanzineEditorState> emit) async {
    emit(FanzineEditorLoading());

    await _fanzineSub?.cancel();
    await _pagesSub?.cancel();

    // We use a Completer to wait for the first data emissions before continuing
    final firstDataReceived = Completer<void>();

    _fanzineSub = _repository.watchFanzine(fanzineId).listen((fzDoc) {
      if (!fzDoc.exists) {
        addError("Fanzine not found");
        return;
      }

      _pagesSub ??= _repository.watchPages(fanzineId).listen((pagesSnap) {
        if (!firstDataReceived.isCompleted) firstDataReceived.complete();

        final current = state;
        if (current is FanzineEditorLoaded) {
          emit(current.copyWith(
            fanzineData: fzDoc.data() as Map<String, dynamic>,
            pages: pagesSnap.docs,
          ));
        } else {
          emit(FanzineEditorLoaded(
            fanzineData: fzDoc.data() as Map<String, dynamic>,
            pages: pagesSnap.docs,
          ));
        }
      });
    });

    try {
      await firstDataReceived.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      emit(FanzineEditorFailure("Timeout loading fanzine data."));
    }
  }

  Future<void> _onUpdateTitle(UpdateFanzineTitle event, Emitter<FanzineEditorState> emit) async {
    if (state is! FanzineEditorLoaded) return;
    try {
      await _repository.updateFanzine(fanzineId, {'title': event.title.trim()});
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    }
  }

  Future<void> _onAddPage(AddPageRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;

    emit(current.copyWith(isProcessing: true));
    try {
      await _repository.addPageByShortcode(fanzineId, event.shortcode);
    } catch (e) {
      // Re-emit loaded but with failure logic handled by a listener in UI
    } finally {
      emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
    }
  }

  Future<void> _onReorderPage(ReorderPageRequested event, Emitter<FanzineEditorState> emit) async {
    try {
      await _repository.reorderPage(fanzineId, event.pageDoc, event.delta, event.allPages);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    }
  }

  Future<void> _onToggleStatus(ToggleLiveStatusRequested event, Emitter<FanzineEditorState> emit) async {
    final newStatus = event.currentStatus == 'live' ? 'working' : 'live';
    await _repository.updateFanzine(fanzineId, {'status': newStatus});
  }

  Future<void> _onSoftPublish(SoftPublishRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;

    emit(current.copyWith(isProcessing: true));
    try {
      await _repository.softPublish(fanzineId);
    } finally {
      emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
    }
  }

  @override
  Future<void> close() {
    _fanzineSub?.cancel();
    _pagesSub?.cancel();
    return super.close();
  }
}