import 'dart:typed_data';
import 'package:flutter/material.dart'; // Added for decodeImageFromList
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

class UploadFolioAssetRequested extends UploadEvent {
  final Uint8List bytes;
  final String fileName;
  final String fanzineId;
  final String userId;

  UploadFolioAssetRequested({
    required this.bytes,
    required this.fileName,
    required this.fanzineId,
    required this.userId,
  });
}

class ResetUploadState extends UploadEvent {}

// --- STATE ---
enum UploadStatus { initial, ready, submitting, success, failure, folioAssetSubmitting, folioAssetSuccess }

class UploadState extends Equatable {
  final UploadStatus status;
  final Uint8List? imageBytes;
  final String? fileName;
  final List<Map<String, dynamic>> creators;
  final String? errorMessage;

  // Fields for folio asset upload results
  final String? uploadedImageId;
  final String? uploadedImageUrl;
  final bool? is5x8;
  final int? width;
  final int? height;

  const UploadState({
    this.status = UploadStatus.initial,
    this.imageBytes,
    this.fileName,
    this.creators = const [],
    this.errorMessage,
    this.uploadedImageId,
    this.uploadedImageUrl,
    this.is5x8,
    this.width,
    this.height,
  });

  UploadState copyWith({
    UploadStatus? status,
    Uint8List? imageBytes,
    String? fileName,
    List<Map<String, dynamic>>? creators,
    String? errorMessage,
    String? uploadedImageId,
    String? uploadedImageUrl,
    bool? is5x8,
    int? width,
    int? height,
  }) {
    return UploadState(
      status: status ?? this.status,
      imageBytes: imageBytes ?? this.imageBytes,
      fileName: fileName ?? this.fileName,
      creators: creators ?? this.creators,
      errorMessage: errorMessage,
      uploadedImageId: uploadedImageId ?? this.uploadedImageId,
      uploadedImageUrl: uploadedImageUrl ?? this.uploadedImageUrl,
      is5x8: is5x8 ?? this.is5x8,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  List<Object?> get props => [
    status, imageBytes, fileName, creators, errorMessage,
    uploadedImageId, uploadedImageUrl, is5x8, width, height
  ];
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
    on<UploadFolioAssetRequested>(_onUploadFolioAsset);
    on<ResetUploadState>((event, emit) => emit(const UploadState()));
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

      final decodedImage = await decodeImageFromList(state.imageBytes!);
      final int width = decodedImage.width;
      final int height = decodedImage.height;
      final double ratio = width / height;
      final bool is5x8 = (ratio >= 0.58 && ratio <= 0.67);

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
        'width': width,
        'height': height,
        'aspectRatio': ratio,
        'is5x8': is5x8,
      });

      emit(state.copyWith(status: UploadStatus.success));
    } catch (e) {
      emit(state.copyWith(status: UploadStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onUploadFolioAsset(UploadFolioAssetRequested event, Emitter<UploadState> emit) async {
    emit(state.copyWith(status: UploadStatus.folioAssetSubmitting));

    try {
      final decodedImage = await decodeImageFromList(event.bytes);
      final int width = decodedImage.width;
      final int height = decodedImage.height;
      final double ratio = width / height;
      final bool is5x8 = (ratio >= 0.58 && ratio <= 0.67);

      final String path = 'uploads/${event.userId}/folio_assets/${event.fanzineId}/${DateTime.now().millisecondsSinceEpoch}_${event.fileName}';

      final url = await _repository.uploadBytes(event.bytes, path, 'image/jpeg');

      final imageDocId = await _repository.saveFolioAssetMetadata({
        'uploaderId': event.userId,
        'folioContext': event.fanzineId,
        'usedInFanzines': [event.fanzineId],
        'fileUrl': url,
        'fileName': event.fileName,
        'title': event.fileName,
        'status': 'approved',
        'isFolioAsset': true,
        'width': width,
        'height': height,
        'aspectRatio': ratio,
        'is5x8': is5x8,
        'storagePath': path,
      });

      emit(state.copyWith(
        status: UploadStatus.folioAssetSuccess,
        uploadedImageId: imageDocId,
        uploadedImageUrl: url,
        is5x8: is5x8,
        width: width,
        height: height,
      ));
    } catch (e) {
      emit(state.copyWith(status: UploadStatus.failure, errorMessage: e.toString()));
    }
  }
}