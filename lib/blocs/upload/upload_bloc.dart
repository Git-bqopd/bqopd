import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../repositories/upload_repository.dart';

// --- EVENTS ---
abstract class UploadEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class ImagePicked extends UploadEvent {
  final Uint8List bytes;
  final String fileName;
  ImagePicked(this.bytes, this.fileName);
  @override
  List<Object?> get props => [bytes, fileName];
}

class AddCreatorRequested extends UploadEvent {
  final String handle;
  final String role;
  AddCreatorRequested(this.handle, this.role);
}

class RemoveCreatorRequested extends UploadEvent {
  final int index;
  RemoveCreatorRequested(this.index);
}

class SubmitUploadRequested extends UploadEvent {
  final String userId;
  final String title;
  final String caption;
  final String indicia;
  final List<Map<String, dynamic>> creators;
  SubmitUploadRequested({
    required this.userId,
    required this.title,
    required this.caption,
    required this.indicia,
    required this.creators,
  });
}

// --- STATE ---
enum UploadStatus { initial, ready, submitting, success, failure }

class UploadState extends Equatable {
  final UploadStatus status;
  final Uint8List? imageBytes;
  final String? fileName;
  final List<Map<String, dynamic>> creators;
  final String? errorMessage;

  const UploadState({
    this.status = UploadStatus.initial,
    this.imageBytes,
    this.fileName,
    this.creators = const [],
    this.errorMessage,
  });

  UploadState copyWith({
    UploadStatus? status,
    Uint8List? imageBytes,
    String? fileName,
    List<Map<String, dynamic>>? creators,
    String? errorMessage,
  }) {
    return UploadState(
      status: status ?? this.status,
      imageBytes: imageBytes ?? this.imageBytes,
      fileName: fileName ?? this.fileName,
      creators: creators ?? this.creators,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, imageBytes, fileName, creators, errorMessage];
}

// --- BLOC ---
class UploadBloc extends Bloc<UploadEvent, UploadState> {
  final UploadRepository _repository;

  UploadBloc({required UploadRepository repository})
      : _repository = repository,
        super(const UploadState()) {
    on<ImagePicked>((event, emit) => emit(state.copyWith(
      status: UploadStatus.ready,
      imageBytes: event.bytes,
      fileName: event.fileName,
    )));

    on<AddCreatorRequested>(_onAddCreator);
    on<RemoveCreatorRequested>((event, emit) {
      final newList = List<Map<String, dynamic>>.from(state.creators)..removeAt(event.index);
      emit(state.copyWith(creators: newList));
    });

    on<SubmitUploadRequested>(_onSubmitUpload);
  }

  Future<void> _onAddCreator(AddCreatorRequested event, Emitter<UploadState> emit) async {
    final result = await _repository.lookupUserByHandle(event.handle);
    final String name = result != null ? result['name'] : event.handle;
    final String? uid = result?['uid'];

    final newList = List<Map<String, dynamic>>.from(state.creators)
      ..add({'uid': uid, 'name': name, 'role': event.role});
    emit(state.copyWith(creators: newList));
  }

  Future<void> _onSubmitUpload(SubmitUploadRequested event, Emitter<UploadState> emit) async {
    if (state.imageBytes == null) return;
    emit(state.copyWith(status: UploadStatus.submitting));

    try {
      final String path = 'uploads/${event.userId}/${DateTime.now().millisecondsSinceEpoch}_${state.fileName}';

      final url = await _repository.uploadBytes(state.imageBytes!, path, 'image/jpeg');

      await _repository.saveImageMetadata({
        'uid': event.userId,
        'uploaderId': event.userId,
        'fileUrl': url,
        'fileName': state.fileName,
        'title': event.title,
        'description': event.caption,
        'status': 'pending',
        'tags': {},
        'indicia': event.indicia,
        'creators': event.creators,
      });

      emit(state.copyWith(status: UploadStatus.success));
    } catch (e) {
      emit(state.copyWith(status: UploadStatus.failure, errorMessage: e.toString()));
    }
  }
}