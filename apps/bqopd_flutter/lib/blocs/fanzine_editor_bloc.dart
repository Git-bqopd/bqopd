import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../repositories/fanzine_repository.dart';
import '../../repositories/pipeline_repository.dart';
import '../../models/fanzine.dart';
import '../../models/fanzine_page.dart';

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

class _FanzineUpdated extends FanzineEditorEvent {
  final Fanzine fanzine;
  _FanzineUpdated(this.fanzine);
  @override
  List<Object?> get props => [fanzine];
}

class _PagesUpdated extends FanzineEditorEvent {
  final List<FanzinePage> pages;
  _PagesUpdated(this.pages);
  @override
  List<Object?> get props => [pages];
}

class UpdateFanzineMetadata extends FanzineEditorEvent {
  final String title;
  final String volume;
  final String issue;
  final String wholeNumber;
  UpdateFanzineMetadata(this.title, this.volume, this.issue, this.wholeNumber);
  @override
  List<Object?> get props => [title, volume, issue, wholeNumber];
}

class ToggleTwoPageRequested extends FanzineEditorEvent {
  final bool twoPage;
  ToggleTwoPageRequested(this.twoPage);
  @override
  List<Object?> get props => [twoPage];
}

class ToggleHasCoverRequested extends FanzineEditorEvent {
  final bool hasCover;
  ToggleHasCoverRequested(this.hasCover);
  @override
  List<Object?> get props => [hasCover];
}

class AddPageRequested extends FanzineEditorEvent {
  final String shortcode;
  AddPageRequested(this.shortcode);
  @override
  List<Object?> get props => [shortcode];
}

class AddExistingImageRequested extends FanzineEditorEvent {
  final String imageId;
  final String imageUrl;
  final int? width;
  final int? height;
  AddExistingImageRequested(this.imageId, this.imageUrl, {this.width, this.height});
}

class UpdatePageLayoutRequested extends FanzineEditorEvent {
  final FanzinePage page;
  final String? spreadPosition;
  final String sidePreference;
  final List<FanzinePage> allPages;
  UpdatePageLayoutRequested(this.page, this.spreadPosition, this.sidePreference, this.allPages);
}

class TogglePageOrderingRequested extends FanzineEditorEvent {
  final FanzinePage page;
  final bool shouldOrder;
  TogglePageOrderingRequested(this.page, this.shouldOrder);
}

class RemovePageRequested extends FanzineEditorEvent {
  final FanzinePage page;
  final List<FanzinePage> allPages;
  RemovePageRequested(this.page, this.allPages);
}

class DeleteAssetRequested extends FanzineEditorEvent {
  final String imageId;
  final bool isDirectUpload;
  DeleteAssetRequested(this.imageId, this.isDirectUpload);
}

class ReorderPageRequested extends FanzineEditorEvent {
  final FanzinePage page;
  final int delta;
  final List<FanzinePage> allPages;
  ReorderPageRequested(this.page, this.delta, this.allPages);
}

class ToggleIsLiveRequested extends FanzineEditorEvent {
  final bool isLive;
  ToggleIsLiveRequested(this.isLive);
}

class SoftPublishRequested extends FanzineEditorEvent {}

// Pipeline Triggers
class TriggerAiCleanRequested extends FanzineEditorEvent {}
class TriggerGenerateLinksRequested extends FanzineEditorEvent {}

// --- STATE ---

abstract class FanzineEditorState extends Equatable {
  @override
  List<Object?> get props => [];
}

class FanzineEditorInitial extends FanzineEditorState {}

class FanzineEditorLoading extends FanzineEditorState {}

class FanzineEditorLoaded extends FanzineEditorState {
  final Fanzine fanzine;
  final List<FanzinePage> pages;
  final bool isProcessing;

  FanzineEditorLoaded({
    required this.fanzine,
    required this.pages,
    this.isProcessing = false
  });

  FanzineEditorLoaded copyWith({
    Fanzine? fanzine,
    List<FanzinePage>? pages,
    bool? isProcessing,
  }) {
    return FanzineEditorLoaded(
      fanzine: fanzine ?? this.fanzine,
      pages: pages ?? this.pages,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  @override
  List<Object?> get props => [fanzine, pages, isProcessing];
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
  final PipelineRepository _pipelineRepository;
  final String fanzineId;

  StreamSubscription? _fanzineSub;
  StreamSubscription? _pagesSub;

  Fanzine? _latestFanzine;
  List<FanzinePage>? _latestPages;

  FanzineEditorBloc({
    required FanzineRepository repository,
    required PipelineRepository pipelineRepository,
    required this.fanzineId
  }) : _repository = repository,
        _pipelineRepository = pipelineRepository,
        super(FanzineEditorInitial()) {
    on<LoadFanzineRequested>(_onLoadRequested);
    on<_FanzineUpdated>(_onFanzineUpdated);
    on<_PagesUpdated>(_onPagesUpdated);
    on<UpdateFanzineMetadata>(_onUpdateMetadata);
    on<ToggleTwoPageRequested>(_onToggleTwoPage);
    on<ToggleHasCoverRequested>(_onToggleHasCover);
    on<AddPageRequested>(_onAddPage);
    on<AddExistingImageRequested>(_onAddExistingImage);
    on<UpdatePageLayoutRequested>(_onUpdatePageLayout);
    on<TogglePageOrderingRequested>(_onTogglePageOrdering);
    on<RemovePageRequested>(_onRemovePage);
    on<DeleteAssetRequested>(_onDeleteAsset);
    on<ReorderPageRequested>(_onReorderPage);
    on<ToggleIsLiveRequested>(_onToggleIsLive);
    on<SoftPublishRequested>(_onSoftPublish);
    on<TriggerAiCleanRequested>(_onTriggerAiClean);
    on<TriggerGenerateLinksRequested>(_onTriggerGenerateLinks);
  }

  Future<void> _onLoadRequested(LoadFanzineRequested event, Emitter<FanzineEditorState> emit) async {
    emit(FanzineEditorLoading());
    await _fanzineSub?.cancel();
    await _pagesSub?.cancel();
    _latestFanzine = null;
    _latestPages = null;

    _fanzineSub = _repository.watchFanzineModel(fanzineId).listen((fzModel) {
      add(_FanzineUpdated(fzModel));
    });

    _pagesSub = _repository.watchPageModels(fanzineId).listen((pages) {
      add(_PagesUpdated(pages));
    });
  }

  void _onFanzineUpdated(_FanzineUpdated event, Emitter<FanzineEditorState> emit) {
    _latestFanzine = event.fanzine;
    _checkAndEmitLoaded(emit);
  }

  void _onPagesUpdated(_PagesUpdated event, Emitter<FanzineEditorState> emit) {
    _latestPages = event.pages;
    _checkAndEmitLoaded(emit);
  }

  void _checkAndEmitLoaded(Emitter<FanzineEditorState> emit) {
    if (_latestFanzine != null && _latestPages != null) {
      final bool wasProcessing = (state is FanzineEditorLoaded)
          ? (state as FanzineEditorLoaded).isProcessing
          : false;

      emit(FanzineEditorLoaded(
        fanzine: _latestFanzine!,
        pages: _latestPages!,
        isProcessing: wasProcessing,
      ));
    }
  }

  Future<void> _onUpdateMetadata(UpdateFanzineMetadata event, Emitter<FanzineEditorState> emit) async {
    if (state is! FanzineEditorLoaded) return;
    try {
      await _repository.updateFanzine(fanzineId, {
        'title': event.title.trim(),
        'volume': event.volume.trim(),
        'issue': event.issue.trim(),
        'wholeNumber': event.wholeNumber.trim(),
      });
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    }
  }

  Future<void> _onToggleTwoPage(ToggleTwoPageRequested event, Emitter<FanzineEditorState> emit) async {
    if (state is! FanzineEditorLoaded) return;
    try {
      await _repository.updateFanzine(fanzineId, {'twoPage': event.twoPage});
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    }
  }

  Future<void> _onToggleHasCover(ToggleHasCoverRequested event, Emitter<FanzineEditorState> emit) async {
    if (state is! FanzineEditorLoaded) return;
    try {
      await _repository.updateFanzine(fanzineId, {'hasCover': event.hasCover});
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
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  Future<void> _onAddExistingImage(AddExistingImageRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;
    emit(current.copyWith(isProcessing: true));
    try {
      await _repository.addExistingImageToFolio(
        fanzineId,
        event.imageId,
        event.imageUrl,
        width: event.width,
        height: event.height,
      );
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  Future<void> _onUpdatePageLayout(UpdatePageLayoutRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;
    emit(current.copyWith(isProcessing: true));
    try {
      await _repository.updatePageLayout(fanzineId, event.page, event.spreadPosition, event.sidePreference, event.allPages);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  Future<void> _onTogglePageOrdering(TogglePageOrderingRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;
    emit(current.copyWith(isProcessing: true));
    try {
      await _repository.togglePageOrdering(fanzineId, event.page, event.shouldOrder);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  Future<void> _onRemovePage(RemovePageRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;
    emit(current.copyWith(isProcessing: true));
    try {
      await _repository.removePageFromFolio(fanzineId, event.page, event.allPages);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  Future<void> _onDeleteAsset(DeleteAssetRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;
    emit(current.copyWith(isProcessing: true));
    try {
      await _repository.deleteAssetCompletely(fanzineId, event.imageId, event.isDirectUpload);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  Future<void> _onReorderPage(ReorderPageRequested event, Emitter<FanzineEditorState> emit) async {
    try {
      await _repository.reorderPageModel(fanzineId, event.page, event.delta, event.allPages);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    }
  }

  Future<void> _onToggleIsLive(ToggleIsLiveRequested event, Emitter<FanzineEditorState> emit) async {
    try {
      await _repository.updateFanzine(fanzineId, {'isLive': event.isLive});
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    }
  }

  Future<void> _onSoftPublish(SoftPublishRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;
    emit(current.copyWith(isProcessing: true));
    try {
      await _repository.softPublish(fanzineId);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  Future<void> _onTriggerAiClean(TriggerAiCleanRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;
    emit(current.copyWith(isProcessing: true));
    try {
      await _pipelineRepository.triggerAiClean(fanzineId);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  Future<void> _onTriggerGenerateLinks(TriggerGenerateLinksRequested event, Emitter<FanzineEditorState> emit) async {
    final current = state;
    if (current is! FanzineEditorLoaded) return;
    emit(current.copyWith(isProcessing: true));
    try {
      await _pipelineRepository.triggerGenerateLinks(fanzineId);
    } catch (e) {
      emit(FanzineEditorFailure(e.toString()));
    } finally {
      if (state is FanzineEditorLoaded) {
        emit((state as FanzineEditorLoaded).copyWith(isProcessing: false));
      }
    }
  }

  @override
  Future<void> close() {
    _fanzineSub?.cancel();
    _pagesSub?.cancel();
    return super.close();
  }
}