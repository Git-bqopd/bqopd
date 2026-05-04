import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../repositories/fanzine_repository.dart';

// --- EVENTS ---

abstract class CalendarEditorEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class UpdateCalendarSettingsRequested extends CalendarEditorEvent {
  final String folioId;
  final String title;
  final int startMonth;
  final int startYear;

  UpdateCalendarSettingsRequested(
      this.folioId,
      this.title,
      this.startMonth,
      this.startYear,
      );

  @override
  List<Object?> get props => [folioId, title, startMonth, startYear];
}

class AddConventionRequested extends CalendarEditorEvent {
  final Map<String, dynamic> conventionData;

  AddConventionRequested(this.conventionData);

  @override
  List<Object?> get props => [conventionData];
}

class DeleteConventionRequested extends CalendarEditorEvent {
  final String conventionId;

  DeleteConventionRequested(this.conventionId);

  @override
  List<Object?> get props => [conventionId];
}

class ToggleSpreadRequested extends CalendarEditorEvent {
  final String folioId;
  final String pageId;
  final bool isSpread;

  ToggleSpreadRequested(this.folioId, this.pageId, this.isSpread);

  @override
  List<Object?> get props => [folioId, pageId, isSpread];
}

// --- STATE ---

enum CalendarEditorStatus { initial, loading, success, failure }

class CalendarEditorState extends Equatable {
  final CalendarEditorStatus status;
  final String? message;

  const CalendarEditorState({
    this.status = CalendarEditorStatus.initial,
    this.message,
  });

  @override
  List<Object?> get props => [status, message];
}

// --- BLOC ---

class CalendarEditorBloc extends Bloc<CalendarEditorEvent, CalendarEditorState> {
  final FanzineRepository _repository;

  CalendarEditorBloc({required FanzineRepository repository})
      : _repository = repository,
        super(const CalendarEditorState()) {
    on<UpdateCalendarSettingsRequested>(_onUpdateSettings);
    on<AddConventionRequested>(_onAddConvention);
    on<DeleteConventionRequested>(_onDeleteConvention);
    on<ToggleSpreadRequested>(_onToggleSpread);
  }

  Future<void> _onUpdateSettings(
      UpdateCalendarSettingsRequested event, Emitter<CalendarEditorState> emit) async {
    emit(const CalendarEditorState(status: CalendarEditorStatus.loading));
    try {
      await _repository.updateCalendarSettings(
          event.folioId, event.title, event.startMonth, event.startYear);
      emit(const CalendarEditorState(
          status: CalendarEditorStatus.success, message: "Calendar Saved!"));
    } catch (e) {
      emit(CalendarEditorState(
          status: CalendarEditorStatus.failure, message: e.toString()));
    }
  }

  Future<void> _onAddConvention(
      AddConventionRequested event, Emitter<CalendarEditorState> emit) async {
    emit(const CalendarEditorState(status: CalendarEditorStatus.loading));
    try {
      await _repository.addConvention(event.conventionData);
      emit(const CalendarEditorState(
          status: CalendarEditorStatus.success, message: "Convention added to Folio!"));
    } catch (e) {
      emit(CalendarEditorState(
          status: CalendarEditorStatus.failure, message: e.toString()));
    }
  }

  Future<void> _onDeleteConvention(
      DeleteConventionRequested event, Emitter<CalendarEditorState> emit) async {
    emit(const CalendarEditorState(status: CalendarEditorStatus.loading));
    try {
      await _repository.deleteConvention(event.conventionId);
      emit(const CalendarEditorState(status: CalendarEditorStatus.success));
    } catch (e) {
      emit(CalendarEditorState(
          status: CalendarEditorStatus.failure, message: e.toString()));
    }
  }

  Future<void> _onToggleSpread(
      ToggleSpreadRequested event, Emitter<CalendarEditorState> emit) async {
    try {
      await _repository.togglePageSpread(event.folioId, event.pageId, event.isSpread);
    } catch (e) {
      emit(CalendarEditorState(
          status: CalendarEditorStatus.failure, message: e.toString()));
    }
  }
}